module SlamData.Workspace.Card.BuildChart.Funnel.Eval
  ( eval
  , module SlamData.Workspace.Card.BuildChart.Funnel.Model
  ) where

import SlamData.Prelude

import Data.Argonaut (JArray, JCursor, Json, cursorGet, toNumber, toString)
import Data.Array as A
import Data.Foldable as F
import Data.Lens ((^?))
import Data.Lens as Lens
import Data.Map as M
import Data.Int as Int
import Data.Set as Set

import ECharts.Monad (DSL)
import ECharts.Commands as E
import ECharts.Types as ET
import ECharts.Types.Phantom (OptionI)
import ECharts.Types.Phantom as ETP

import Quasar.Types (FilePath)

import SlamData.Common.Sort (Sort(..))
import SlamData.Common.Align (Align(..))
import SlamData.Quasar.Class (class QuasarDSL)
import SlamData.Quasar.Error as QE
import SlamData.Quasar.Query as QQ
import SlamData.Form.Select (_value)
import SlamData.Workspace.Card.BuildChart.Funnel.Model (Model, FunnelR)
import SlamData.Workspace.Card.CardType.ChartType (ChartType(Funnel))
import SlamData.Workspace.Card.Chart.Aggregation as Ag
import SlamData.Workspace.Card.Chart.Axis (Axis, Axes, analyzeJArray)
import SlamData.Workspace.Card.Chart.Axis as Ax
import SlamData.Workspace.Card.Chart.BuildOptions.ColorScheme (colors)
import SlamData.Workspace.Card.Chart.Semantics as Sem
import SlamData.Workspace.Card.Eval.CardEvalT as CET
import SlamData.Workspace.Card.Port as Port


eval
  ∷ ∀ m
  . (Monad m, QuasarDSL m)
  ⇒ Model
  → FilePath
  → CET.CardEvalT m Port.Port
eval Nothing _ =
  QE.throw "Please select axis to aggregate"
eval (Just conf) resource = do
  numRecords ←
    CET.liftQ $ QQ.count resource

  when (numRecords > 10000)
    $ QE.throw
    $ "The 10000 record limit for visualizations has been exceeded - the current dataset contains "
    ⊕ show numRecords
    ⊕ " records. "
    ⊕ "Please consider using a 'limit' or 'group by' clause in the query to reduce the result size."

  records ←
    CET.liftQ $ QQ.all resource

  pure $ Port.ChartInstructions (buildFunnel conf records) Funnel

infixr 3 type M.Map as >>

type FunnelSeries =
  { name ∷ Maybe String
  , items ∷ String >> Number
  , x ∷ Maybe Number
  , y ∷ Maybe Number
  , w ∷ Maybe Number
  , h ∷ Maybe Number
  }

buildFunnelData ∷ FunnelR → JArray → Array FunnelSeries
buildFunnelData r records = series
  where
  -- | maybe series >> category >> values
  dataMap ∷ Maybe String >> String >> Array Number
  dataMap =
    foldl dataMapFoldFn M.empty records

  dataMapFoldFn
    ∷ Maybe String >> String >> Array Number
    → Json
    → Maybe String >> String >> Array Number
  dataMapFoldFn acc js =
    case toString =<< cursorGet r.category js of
      Nothing → acc
      Just categoryKey →
        let
          mbSeries = toString =<< flip cursorGet js =<< r.series
          values = foldMap A.singleton $ toNumber =<< cursorGet r.value js

          alterSeriesFn
            ∷ Maybe (String >> Array Number)
            → Maybe (String >> Array Number)
          alterSeriesFn Nothing =
            Just $ M.singleton mbSeries $ M.singleton categoryKey values
          alterSeriesFn (Just series) =
            Just $ M.alter alterSeriesFn mbSeries series

          alterSeriesFn
            ∷ Maybe (Array Number)
            → Maybe (Array Number)
          alterSeriesFn Nothing = Just values
          alterSeriesFn (Just arr) = Just $ arr ⊕ values
        in
          M.alter alterSeriesFn mbSeries acc

  rawSeries ∷ Array FunnelSeries
  rawSeries =
    foldMap mkOneSeries $ M.toList dataMap

  mkOneSeries
    ∷ Maybe String × (String >> Array Number)
    → Array FunnelSeries
  mkOneSeries (name × series) =
    [{ name
     , x: Nothing
     , y: Nothing
     , w: Nothing
     , h: Nothing
     , items: map (Ag.runAggregation r.valueAggregation) series
     }]

  series ∷ Array FunnelSeries
  series = adjustPosition rawSeries

  adjustPosition ∷ Array FunnelSeries → Array FunnelSeries
  adjustPosition = id


buildFunnel ∷ FunnelR → JArray → DSL OptionI
buildFunnel r records = do
  E.tooltip do
    E.triggerItem
    E.textStyle do
      E.fontFamily "Ubuntu, sans"
      E.fontSize 122

    E.legend do
      E.items $ map ET.strItem legendNames
      E.topBottom
      E.textStyle do
        E.fontFamily "Ubuntu, sans"

    E.colors colors

    E.titles
      $ traverse_ E.title titles

    E.series series

  where
  funnelData ∷ Array FunnelSeries
  funnelData = buildFunnelData r records

  legendNames ∷ Array String
  legendNames =
    A.fromFoldable
      $ foldMap (_.name ⋙ foldMap Set.singleton) funnelData

  titles ∷ Array (DSL ETP.TitleI)
  titles = funnelData <#> \{name, x, y} → do
    for_ name E.text
    E.textStyle do
      E.fontFamily "Ubunut, sans"
      E.fontSize 12
    traverse_ (E.top ∘ ET.Percent) y
    traverse_ (E.left ∘ ET.Percent) x
    E.textCenter
    E.textBottom

  series = for_ funnelData \{x, y, w, h, items} → E.pie do
    E.left $ ET.Percent x
    E.top $ ET.Percent y
    E.widthPct w
    E.heightPct h
    for_ name E.name
    case r.order of
      Asc → E.ascending
      Desc → E.descending
    case r.align of
      LeftAlign → E.funnelLeft
      RightAlign → E.funnelRight
      CenterAlign → E.funnelCenter
    E.label $ E.normal $ E.textStyle $ E.fontFamily "Ubuntu, sans"
    E.buildItems $ for_ (M.toList items) \(name × value) → do
      E.name name
      E.value value
    traverse_ (E.top ∘ ET.Percent) y
    traverse_ (E.left ∘ ET.Percent) x