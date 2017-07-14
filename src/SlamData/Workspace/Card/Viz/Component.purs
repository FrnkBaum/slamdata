module SlamData.Workspace.Card.Viz.Component where

import SlamData.Prelude


import Data.Array as A
import Data.Foreign as F
import Data.Foreign.Index (readProp)
import Data.Int (toNumber, floor)
import Data.Lens ((^?), _Just)
import Data.String as S
import Data.Variant (on)

import Global (readFloat, isNaN)

import Halogen as H
import Halogen.ECharts as HEC
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

import SlamData.Render.ClassName as CN
import SlamData.Wiring as Wiring
import SlamData.Workspace.Card.CardType as CT
import SlamData.Workspace.Card.Component as CC
import SlamData.Workspace.Card.Eval.State as ES
import SlamData.Workspace.Card.Model as Card
import SlamData.Workspace.Card.Port (Port(..))
import SlamData.Workspace.Card.Viz.Component.ChildSlot as CS
import SlamData.Workspace.Card.Viz.Component.Query as Q
import SlamData.Workspace.Card.Viz.Component.State as ST
import SlamData.Workspace.Card.Viz.Model as M
import SlamData.Workspace.Card.Viz.Renderer.Input.Component as IR
import SlamData.Workspace.Card.Viz.Renderer.Metric.Component as MR
import SlamData.Workspace.Card.Viz.Renderer.PivotTable.Component as PR
import SlamData.Workspace.Card.Viz.Renderer.Select.Component as SR
import SlamData.Workspace.Card.Viz.Renderer.Geo.Component as GR
import SlamData.Workspace.LevelOfDetails as LOD

import Utils (hush')

type HTML = CC.InnerCardParentHTML Q.Query CS.ChildQuery CS.ChildSlot
type DSL = CC.InnerCardParentDSL ST.State Q.Query CS.ChildQuery CS.ChildSlot

component ∷ CC.CardOptions → CC.CardComponent
component =
  CC.makeCardComponent CT.viz $ H.lifecycleParentComponent
    { render: render
    , eval: evalCard ⨁ evalComponent
    , initialState: const ST.initialState
    , initializer: Just $ right $ H.action Q.Init
    , finalizer: Nothing
    , receiver: const Nothing
    }

render ∷ ST.State → HTML
render state =
  HH.div
    [ HP.classes [ CN.chartOutput, HH.ClassName "card-input-maximum-lod" ] ]
    $ foldMap dispatchVizType state.vizType
  where
  chartDimensions ∷ { width ∷ Int, height ∷ Int }
  chartDimensions = state.dimensions { height = state.dimensions.height - 60 }

  dispatchVizType ∷ CT.VizType → Array HTML
  dispatchVizType vt
    | isJust $ CT.upcastToInput vt = renderInput
    | isJust $ CT.upcastToStatic vt = renderMetric
    | isJust $ CT.upcastToSelect vt = renderSelect
    | isJust $ CT.upcastToGeo vt = renderGeo
    | isJust (upcast vt ∷ Maybe (Variant (pivot ∷ Unit))) = renderPivot
    | isJust (upcast vt ∷ Maybe (Variant (metric ∷ Unit))) = renderMetric
    | otherwise = renderEChart

  renderEChart ∷ Array HTML
  renderEChart =
    flip foldMap state.theme \theme →
    A.singleton
    $ HH.slot' CS.cpECharts unit
      (HEC.echarts theme)
      (chartDimensions × unit)
      (const Nothing)

  renderMetric ∷ Array HTML
  renderMetric =
    A.singleton
    $ HH.slot' CS.cpMetric unit
      MR.component
      state.dimensions
      absurd

  renderPivot ∷ Array HTML
  renderPivot =
    A.singleton
    $ HH.slot' CS.cpPivotTable unit
      PR.component
      unit
      (Just ∘ right <$> handlePivotTableMessage)

  renderSelect ∷ Array HTML
  renderSelect =
    A.singleton
    $ HH.slot' CS.cpSelect unit
      SR.component
      unit
      (HE.input_ $ right ∘ Q.RaiseUpdate Nothing)

  renderInput ∷ Array HTML
  renderInput =
    A.singleton
    $ HH.slot' CS.cpInput unit
      IR.component
      unit
      (HE.input_ $ right ∘ Q.RaiseUpdate Nothing)

  renderGeo ∷ Array HTML
  renderGeo =
    A.singleton
    $ HH.slot' CS.cpGeo unit
      GR.component
      unit
      (HE.input $ \f → right ∘ Q.RaiseUpdate (Just f))

evalCard ∷ CC.CardEvalQuery ~> DSL
evalCard = case _ of
  CC.Activate next →
    pure next
  CC.Deactivate next →
    pure next
  CC.Save k → do
    mvt ← H.gets _.vizType
    case mvt of
      Nothing → pure $ k $ Card.Viz $ M.chart unit
      Just vt → do
        mm ← for (upcast vt ∷ Maybe (Variant (metric ∷ Unit, static ∷ Unit))) \_ →
          pure $ M.metric unit
        im ← for (CT.upcastToInput vt) \_ → do
          res ← H.query' CS.cpInput unit $ H.request IR.Save
          pure $ map M.input res
        pm ← for (upcast vt ∷ Maybe (Variant (pivot ∷ Unit))) \_ → do
          res ← H.query' CS.cpPivotTable unit $ H.request PR.Save
          pure $ map M.pivot res
        sm ← for (CT.upcastToSelect vt) \_ → do
          res ← H.query' CS.cpSelect unit $ H.request SR.Save
          pure $ map M.select res
        gm ← for (CT.upcastToGeo vt) \_ → do
          res ← H.query' CS.cpGeo unit $ H.request GR.Save
          pure $ map M.geo res
        pure $ k $ Card.Viz
          $ fromMaybe (M.chart unit)
          $ mm <|> join im <|> join pm <|> join sm <|> join gm

  CC.Load model next →
    case model of
      Card.Viz vm → case_
        # on M._pivot (\m → do
                          H.modify _{ vizType = Just CT.pivot }
                          _ ← H.query' CS.cpPivotTable unit $ H.action $ PR.Load m
                          pure next
                      )
        # on M._select (\m → do
                           H.modify _{ vizType = Just $ downcast m.formInputType }
                           _ ← H.query' CS.cpSelect unit $ H.action $ SR.Load m
                           pure next
                       )
        # on M._input (\m → do
                          H.modify _{ vizType = Just $ downcast m.formInputType }
                          _ ← H.query' CS.cpInput unit $ H.action $ IR.Load m
                          pure next
                      )
        # on M._geo (\m → do
                        H.modify _{ vizType = Just CT.geoMarker }
                        _ ← H.query' CS.cpGeo unit $ H.action $ GR.Load m
                        pure next
                    )
        # on M._static (const $ H.modify _{ vizType = Just CT.static } $> next )
        # on M._metric (const $ H.modify _{ vizType = Just CT.metric } $> next )
        # on M._chart (const $ H.modify _{ vizType = Just CT.pie } $> next )
        $ vm
      _ →
        pure next
  CC.ReceiveInput input varMap next → do
    case input of
      SetupInput p → void do
        H.modify _{ vizType = Just $ downcast p.formInputType }
        H.query' CS.cpInput unit $ H.action $ IR.Setup p
      SetupLabeledFormInput p → void do
        H.modify _{ vizType = Just $ downcast p.formInputType }
        H.query' CS.cpSelect unit $ H.action $ SR.Setup p
      CategoricalMetric m → void do
        H.modify _{ vizType = Just CT.static }
        H.query' CS.cpMetric unit $ H.action $ MR.SetMetric m
      ChartInstructions r → void do
        H.modify _{ vizType = Just $ downcast r.chartType }
      ValueMetric m → void do
        H.modify _{ vizType = Just CT.metric }
        H.query' CS.cpMetric unit $ H.action $ MR.SetMetric m
      PivotTable _ → void do
        H.modify _{ vizType = Just CT.pivot }
      GeoChart m → void do
        H.modify _{ vizType = Just CT.geoMarker }
        H.query' CS.cpGeo unit $ H.action $ GR.Setup m
      _ → void do
        H.query' CS.cpECharts unit $ H.action HEC.Clear
    pure next
  CC.ReceiveOutput _ _ next →
    pure next
  CC.ReceiveState evalState next → do
    case evalState of
      ES.ChartOptions options → void do
        _ ← H.query' CS.cpECharts unit $ H.action $ HEC.Reset options
        H.query' CS.cpECharts unit $ H.action HEC.Resize
      ES.PivotTable options → void do
        H.query' CS.cpPivotTable unit $ H.action $ PR.Update options
      ES.AutoSelect {autoSelect} → void do
        H.query' CS.cpSelect unit $ H.action $ SR.SetSelected autoSelect
      ES.Geo geo → void do
        H.query' CS.cpGeo unit $ H.action $ GR.Update geo
      _ → pure unit
    pure next
  CC.ReceiveDimensions dims reply → do
    state ← H.get
    let
      widthPadding = 6
      geoPadding = 10
      intWidth = floor dims.width - widthPadding
      intHeight = floor dims.height
    H.modify _{ dimensions = { width: intWidth, height: intHeight } }
    map reply $ maybe (pure LOD.High) lodByChartType state.vizType


resizeGeo ∷ DSL Unit
resizeGeo = void do
  state ← H.get
  let padding = 16
      width = state.dimensions.width - padding
      height = state.dimensions.height - padding
  H.query' CS.cpGeo unit $ H.action $ GR.SetDimensions { width, height }

lodByChartType ∷ CT.VizType → DSL LOD.LevelOfDetails
lodByChartType vt
  | isJust (upcast vt ∷ Maybe (Variant (pivot ∷ Unit))) =
      pure LOD.High
  | isJust (upcast vt ∷ Maybe (Variant (static ∷ Unit, metric ∷ Unit))) = do
      mblod ← H.query' CS.cpMetric unit $ H.request MR.GetLOD
      pure $ fromMaybe LOD.Low mblod
  | (isJust (CT.upcastToSelect vt) ∨ isJust (CT.upcastToInput vt)) = do
      width ← H.gets _.dimensions.width
      pure if width < 240 then LOD.Low else LOD.High
  | otherwise = do
    { width, height } ← H.gets _.dimensions
    mbOpts ← H.query' CS.cpECharts unit $ H.request HEC.GetOptions
    let
      eBottom = do
        fOption ← join mbOpts
        grids ← hush' $ F.readArray =<< readProp "grid" fOption
        grid ← A.head grids
        hush' $ readProp "bottom" grid

      eBottomPx = hush' ∘ F.readInt =<< eBottom

      eBottomPct = do
        pctStr ← hush' ∘ F.readString =<< eBottom
        str ← S.stripSuffix (S.Pattern "%") pctStr
        let num = readFloat str
        guard (not $ isNaN num)
        pure $ floor $ num / 100.0 * toNumber height
    fromMaybe LOD.Low <$> for (eBottomPx <|> eBottomPct <|> pure zero) \bottomPx →
      pure
        if (height - bottomPx) < 200 ∨ width < 300
        then LOD.Low
        else LOD.High

evalComponent ∷ Q.Query ~> DSL
evalComponent = case _ of
  Q.Init next → do
    { echarts } ← H.lift Wiring.expose
    H.modify _{ theme = Just echarts.theme }
    pure next
  Q.RaiseUpdate em next → do
    resizeGeo
    for_ em (H.raise ∘ CC.stateAlter)
    H.raise CC.modelUpdate
    pure next

handlePivotTableMessage ∷ PR.Message → Q.Query Unit
handlePivotTableMessage = case _ of
  PR.ModelUpdated → H.action $ Q.RaiseUpdate Nothing
  PR.StateUpdated f → H.action $ Q.RaiseUpdate (Just (updateFn f))
  where
  updateFn ∷ (ES.PivotTableR → ES.PivotTableR) → Maybe ES.EvalState → Maybe ES.EvalState
  updateFn f s = case s ^? _Just ∘ ES._PivotTable of
    Just p  → Just $ ES.PivotTable (f p)
    Nothing → s
