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

module SlamData.Workspace.Card.PivotTable.Component.Query
  ( Query(..)
  , QueryC
  , QueryP
  ) where

import SlamData.Prelude
import Halogen as H
import SlamData.Workspace.Card.Common.EvalQuery (CardEvalQuery)

data Query a
  = AddDimension Int a
  | RemoveDimension Int a
  | AddColumn Int a
  | RemoveColumn Int a

type QueryC = Coproduct CardEvalQuery Query

type QueryP = H.ParentQuery QueryC (Const Void) Void
