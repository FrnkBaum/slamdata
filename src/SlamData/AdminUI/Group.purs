{-
Copyright 2017 SlamData, Inc.

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

module SlamData.AdminUI.Group where

import SlamData.Prelude

import Data.List as L
import Data.Path.Pathy as Pathy
import Halogen as H
import Halogen.Component.Proxy (proxyQL)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.HalogenM as HQ
import Quasar.Advanced.Types as QA
import SlamData.AdminUI.Group.Item as GI
import SlamData.AdminUI.Types as AT
import SlamData.Monad (Slam)
import SlamData.Quasar.Security (groupInfo)
import SlamData.Render.Icon as I
import SlamData.Workspace.MillerColumns.Column.Component as MCC
import SlamData.Workspace.MillerColumns.Column.Component.Request as MCREQ
import SlamData.Workspace.MillerColumns.Component as Miller
import SlamData.Workspace.MillerColumns.Component.State (ColumnsData)
import Unsafe.Coerce (unsafeCoerce)

type ColumnOptions = MCC.ColumnOptions AT.GroupItem QA.GroupPath AT.GroupMessage
type ColumnQuery = MCC.Query AT.GroupItem QA.GroupPath AT.GroupMessage

type Message' = MCC.Message' AT.GroupItem QA.GroupPath AT.GroupMessage

component
  ∷ ColumnOptions
  → QA.GroupPath
  → H.Component HH.HTML (MCC.Query' AT.GroupItem QA.GroupPath AT.GroupMessage) Input Message' Slam
component opts = proxyQL ∘ component' opts

data Query a = Raise Message' a | SetNewGroupText String a

type Query' = Coproduct ColumnQuery Query

type State = { item ∷ Maybe AT.GroupItem, newGroupText ∷ String, columnWidth ∷ MCC.ColumnWidth }

type DSL = H.ParentDSL State Query' ColumnQuery Unit Message' Slam
type HTML = H.ParentHTML Query' ColumnQuery Unit Slam
type Input = MCC.ColumnWidth × Maybe AT.GroupItem

component'
  ∷ ColumnOptions
  → QA.GroupPath
  → H.Component HH.HTML Query' Input Message' Slam
component' opts path =
  H.parentComponent
    { initialState: \(columnWidth × item) → { item, newGroupText: "", columnWidth }
    , render
    , eval
    , receiver: Just ∘ left ∘ H.action ∘ MCC.HandleInput
    }
  where

  column ∷ H.Component HH.HTML ColumnQuery Input Message' Slam
  column = MCC.component' opts path

  render ∷ State → HTML
  render st =
    HH.div
      [ HP.class_ (HH.ClassName "sd-admin-ui-column") ]
      [ HH.slot unit column (st.columnWidth × st.item) (Just ∘ right ∘ H.action ∘ Raise)
      , HH.form
          [ HP.class_ (HH.ClassName "sd-admin-ui-group-form")
          , HE.onSubmit (\event → Just $ right $ H.action $ Raise $ Right $ AT.AddNewGroup { path, event, name: st.newGroupText })
          ]
          [ HH.input
              [ HP.class_ (HH.ClassName "sd-admin-ui-group-input")
              , HP.value st.newGroupText
              , HE.onValueInput $ \s → Just $ right $ H.action $ SetNewGroupText s
              , HP.placeholder "Add Group"
              ]
          , HH.label
              [ HP.class_ (HH.ClassName "sd-admin-ui-group-input-label") ]
              [ I.addCircle ]
          ]
      ]

  eval ∷ Query' ~> DSL
  eval = coproduct evalInner evalOuter

  evalInner ∷ ColumnQuery ~> DSL
  evalInner =
    maybe (HQ.halt "Inner component query failed") pure <=< H.query unit

  evalOuter ∷ Query ~> DSL
  evalOuter = case _ of
    SetNewGroupText t next → do
      H.modify (_ { newGroupText = t })
      pure next
    Raise msg next → do
      H.raise msg
      pure next

renderGroupsForm ∷ AT.GroupsState → Array AT.HTML
renderGroupsForm (AT.GroupsState _) =
  [ HH.slot' AT.cpGroups unit (Miller.component columnOptions) columnState (HE.input (either AT.HandleColumns AT.HandleColumnOrItem)) ]
  where
    columnState ∷ ColumnsData AT.GroupItem QA.GroupPath
    columnState = QA.GroupPath (Pathy.rootDir) × L.Nil

    columnOptions ∷ Miller.ColumnOptions AT.GroupItem QA.GroupPath AT.GroupMessage
    columnOptions =
      Miller.ColumnOptions
        { renderColumn: component
        , renderItem: GI.component
        , label: AT.groupItemName
        , isLeaf: const false
        , id: \(AT.GroupItem { path }) → path
        }

load
  ∷ Tuple QA.GroupPath { requestId ∷ MCREQ.RequestId, filter ∷ String, offset ∷ Maybe Int }
  → AT.DSL (MCREQ.LoadResponse AT.GroupItem)
load (path × { requestId }) =
  groupInfo path >>= case _ of
    Right { subGroups, members } → do
      items ← traverse groupFromPath subGroups
      pure { requestId
           , items: L.fromFoldable items
           , nextOffset: Nothing
           }
    Left e → pure (noResult requestId)
  where
    groupFromPath ∷ QA.GroupPath → AT.DSL AT.GroupItem
    groupFromPath p = do
      groupInfo p >>= case _ of
        Right { subGroups, members } →
          pure (AT.GroupItem
            { path: p
            , name: QA.printGroupPath p
            })
        Left e →
          -- TODO(Christoph): Ahem
          unsafeCoerce unit

noResult ∷ MCREQ.RequestId → MCREQ.LoadResponse AT.GroupItem
noResult requestId = { requestId, items: L.Nil, nextOffset: Nothing }
