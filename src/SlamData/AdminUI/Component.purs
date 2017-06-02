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

module SlamData.AdminUI.Component
  ( component
  , Query(..)
  , State(..)
  , TabIndex(..)
  , MySettingsState(..)
  , DatabaseState(..)
  , PostgresCon(..)
  ) where

import SlamData.Prelude

import Data.Array as Array
import Data.List (List)
import Data.List as List
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import SlamData.Monad (Slam)

data Query a
  = Init a
  | Open a
  | Close a
  | SetActive TabIndex a
  | SetMySettings MySettingsState a

data TabIndex
  = MySettings
  | Database
  | Server
  | Authentication
  | Users
  | Group

derive instance eqTabIndex ∷ Eq TabIndex
derive instance ordTabIndex ∷ Ord TabIndex
instance showTabIndex ∷ Show TabIndex where
  show = tabTitle

allTabs ∷ List TabIndex
allTabs = List.fromFoldable [MySettings, Database, Server, Authentication, Users, Group]

tabTitle ∷ TabIndex → String
tabTitle = case _ of
  MySettings → "My Settings"
  Database → "Database"
  Server → "Server"
  Authentication → "Authentication"
  Users → "Users"
  Group → "Group"

type State =
  { open ∷ Boolean
  , active ∷ TabIndex
  , formState ∷ { mySettings ∷ MySettingsState, database ∷ DatabaseState }
  }

newtype MySettingsState = MySettingsState
  { homeDirectory ∷ String
  , isolateArtifacts ∷ Boolean
  , isolateArtifactsDirectory ∷ String
  }
defaultMySettingsState ∷ MySettingsState
defaultMySettingsState =
  MySettingsState
    { homeDirectory: ""
    , isolateArtifacts: false
    , isolateArtifactsDirectory: ""
    }

-- TODO(Christoph): Do properly
type PostgresCon = String

data DatabaseState = InternalStorage String | ExternalStorage PostgresCon
defaultDatabaseState ∷ DatabaseState
defaultDatabaseState = InternalStorage "ohai"

type HTML = H.ComponentHTML Query
type DSL = H.ComponentDSL State Query Void Slam

component ∷ H.Component HH.HTML Query Unit Void Slam
component =
  H.lifecycleComponent
    { initialState: \_ →
       { open: false
       , active: MySettings
       , formState:
          { mySettings: defaultMySettingsState
          , database: defaultDatabaseState
          }
       }
    , render
    , eval
    , initializer: Just (H.action Init)
    , finalizer: Nothing
    , receiver: const Nothing
    }

render ∷ State → HTML
render state =
  HH.div
    [ HP.classes $ fold
        [ pure (H.ClassName "sd-admin-ui")
        , guard (not state.open) $> H.ClassName "hidden"
        ]
    ]
    [ tabHeader state.active
    , tabBody state
    , HH.button
        [ HE.onClick (HE.input_ Close) ]
        [ HH.text "Close" ]
    ]

tabHeader ∷ TabIndex → HTML
tabHeader active =
  HH.ul
    [ HP.class_ $ H.ClassName "tabs"]
    $ Array.fromFoldable
    $ allTabs <#> \t →
      HH.li
        (fold
          [ pure $ HE.onClick $ HE.input_ $ SetActive t
          , guard (t == active) $> HP.class_ (H.ClassName "active-tab")
          ])
        [ HH.span_ [ HH.text (tabTitle t) ] ]

tabBody ∷ State → HTML
tabBody state =
  HH.form
    [HP.class_ $ HH.ClassName "tab-body"]
    case state.active of
      MySettings →
        pure $ HH.div
          [ HP.class_ (HH.ClassName "my-settings") ]
          (renderMySettingsForm state.formState.mySettings)
      _ → [HH.text "Not implemented"]
      -- Database → ?x
      -- Server → ?x
      -- Authentication → ?x
      -- Users → ?x
      -- Group → ?x

-- TODO(Christoph): Talk to Kyle
themes ∷ Array String
themes = ["Dark", "Light"]

renderMySettingsForm ∷ MySettingsState → Array HTML
renderMySettingsForm (MySettingsState state) =
    [ HH.fieldset
        [ HP.class_ (HH.ClassName "home-directory") ]
        [ HH.legend_ [ HH.text "Location of my home directory in the SlamData file system:" ]
        , HH.input
            [ HP.classes [ HH.ClassName "form-control" ]
            , HP.id_ "HomeDirectory"
            , HP.value state.homeDirectory
            ]
        , HH.div
            [ HP.classes [ HH.ClassName "form-group" ] ]
            [ HH.div
                [ HP.classes [ HH.ClassName "checkbox" ] ]
                [ HH.label_
                    [ HH.input
                        [ HP.checked state.isolateArtifacts
                        , HP.type_ HP.InputCheckbox
                        ]
                    , HH.text "Isolate SlamData artifacts to a specific location in the SlamData file system"
                    ]
                ]
            , HH.input
                [ HP.classes [ HH.ClassName "form-control" ]
                , HP.id_ "IsolateLocation"
                , HP.disabled (not state.isolateArtifacts)
                , HP.value state.isolateArtifactsDirectory
                ]
            , HH.p_
                [ HH.text $
                  fold
                  [ "If you choose this option, while you can still virtually locate decks anywhere inside the file system, "
                  , "they will always be physically stored in the above location. This allows you to keep production systems "
                  , "free of SlamData artifacts, while still centrally locating and backing them up."
                  ]
                ]
            ]
        ]
    , HH.fieldset
        [ HP.class_ (HH.ClassName "themes") ]
        [ HH.legend_ [ HH.text "Default theme for new decks:" ]
        , HH.div
            [ HP.class_ (HH.ClassName "theme-pickers") ]
            [ HH.select
                [ HP.classes [ HH.ClassName "form-control" ]
                , HP.id_ "ThemeSelection"
                ]
                (themes <#> \t → HH.option_ [HH.text t])
            , HH.select
                [ HP.classes [ HH.ClassName "form-control" ]
                , HP.id_ "ThemeSpacing"
                ]
                (themes <#> \t → HH.option_ [HH.text t])
            ]
        ]
    ]

eval ∷ Query ~> DSL
eval = case _ of
  Init next → do
    pure next
  Open next → do
    H.modify (_ { open = true })
    pure next
  Close next → do
    H.modify (_ { open = false })
    pure next
  SetActive ix next → do
    H.modify (_ { active = ix })
    pure next
  SetMySettings new next → do
    H.modify (_ { formState { mySettings = new } })
    pure next
