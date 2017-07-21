module SlamData.Workspace.Card.Setups.Viz.Component.State where

import SlamData.Prelude

import Data.ListMap as LM
import Data.Variant (inj)
import SlamData.Workspace.Card.CardType as CT
import SlamData.Workspace.Card.CardType.VizType as VT
import SlamData.Workspace.Card.Setups.Auxiliary as Aux
import SlamData.Workspace.Card.Setups.Auxiliary.Area as Area
import SlamData.Workspace.Card.Setups.Auxiliary.Bar as Bar
import SlamData.Workspace.Card.Setups.Auxiliary.Funnel as Funnel
import SlamData.Workspace.Card.Setups.Auxiliary.Gauge as Gauge
import SlamData.Workspace.Card.Setups.Auxiliary.GeoHeatmap as GeoHeatmap
import SlamData.Workspace.Card.Setups.Auxiliary.GeoMarker as GeoMarker
import SlamData.Workspace.Card.Setups.Auxiliary.Graph as Graph
import SlamData.Workspace.Card.Setups.Auxiliary.Heatmap as Heatmap
import SlamData.Workspace.Card.Setups.Auxiliary.Line as Line
import SlamData.Workspace.Card.Setups.Auxiliary.Metric as Metric
import SlamData.Workspace.Card.Setups.Auxiliary.PunchCard as PunchCard
import SlamData.Workspace.Card.Setups.Auxiliary.Scatter as Scatter
import SlamData.Workspace.Card.Setups.Axis as Ax
import SlamData.Workspace.Card.Setups.DimensionMap.Projection as Pr

type State =
  { vizType ∷ Maybe VT.VizType
  , vizTypePickerExpanded ∷ Boolean
  , axes ∷ Maybe Ax.Axes
  , dimMaps ∷ LM.ListMap VT.VizType Pr.DimMap
  , auxes ∷ LM.ListMap VT.VizType Aux.State
  }

initialState ∷ State
initialState =
  { vizType: Nothing
  , vizTypePickerExpanded: false
  , axes: Nothing
  , dimMaps: LM.fromFoldable $ map (_ × Pr.empty) VT.all
  , auxes: LM.fromFoldable
      $ [ CT.geoHeatmap × inj CT._geoHeatmap GeoHeatmap.initial
        , CT.geoMarker × inj CT._geoMarker GeoMarker.initial
        , CT.area × inj CT._area Area.initial
        , CT.bar × inj CT._bar Bar.initial
        , CT.funnel × inj CT._funnel Funnel.initial
        , CT.graph × inj CT._graph Graph.initial
        , CT.heatmap × inj CT._heatmap Heatmap.initial
        , CT.line × inj CT._line Line.initial
        , CT.metric × inj CT._metric Metric.initial
        , CT.punchCard × inj CT._punchCard PunchCard.initial
        , CT.scatter × inj CT._scatter Scatter.initial
        , CT.gauge × inj CT._gauge Gauge.initial
        ]
  }
