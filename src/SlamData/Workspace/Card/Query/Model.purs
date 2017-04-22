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

module SlamData.Workspace.Card.Query.Model
  ( initialModel
  ) where

import SlamData.Prelude

import SlamData.Workspace.Card.Ace.Model as Ace
import SlamData.Workspace.Card.Port as Port

import SqlSquare as Sql

initialModel ∷ Port.Port → Ace.Model
initialModel = case _ of
  Port.ResourceKey var →
    { text: "SELECT * FROM :" <> Sql.printIdent var
    , ranges: []
    }
  _ →
    { text: "SELECT \"Hello, World!\""
    , ranges: []
    }
