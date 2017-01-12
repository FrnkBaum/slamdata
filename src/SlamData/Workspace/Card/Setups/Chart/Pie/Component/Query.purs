{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Workspace.Card.Setups.Chart.Pie.Component.Query where

import SlamData.Prelude

import Data.Argonaut (JCursor)

import Halogen as H

import SlamData.Workspace.Card.Common.EvalQuery (CardEvalQuery)
import SlamData.Workspace.Card.Setups.Chart.Aggregation (Aggregation)
import SlamData.Workspace.Card.Setups.Inputs (SelectAction)
import SlamData.Workspace.Card.Setups.Chart.Pie.Component.ChildSlot (ChildQuery, ChildSlot)

data Selection f
  = Category (f JCursor)
  | Value (f JCursor)
  | ValueAgg (f Aggregation)
  | Donut (f JCursor)
  | Parallel (f JCursor)

data Query a
  = Select (Selection SelectAction) a

type QueryC = CardEvalQuery ⨁ Query

type QueryP = QueryC ⨁ H.ChildF ChildSlot ChildQuery