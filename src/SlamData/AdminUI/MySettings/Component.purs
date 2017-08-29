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

module SlamData.AdminUI.MySettings.Component (component, Query(..)) where

import SlamData.Prelude

import Data.Argonaut as J
import Data.Codec as C
import Data.Path.Pathy (parseAbsDir)
import Data.String as String
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import SlamData.LocalStorage.Class as LS
import SlamData.LocalStorage.Keys as LK
import SlamData.Monad (Slam)
import SlamData.Render.ClassName as CN
import SlamData.Theme.Theme (Theme)
import SlamData.Theme.Theme as Theme
import SlamData.Workspace.Class (changeTheme)
import Utils.Path (sandbox)

data Query a
  = Init a
  | DefaultThemeChanged String a
  | HomeDirectoryChanged String a

type State =
  { homeDirectory ∷ String
  , homeDirectoryError ∷ Maybe String
  , defaultTheme ∷ Theme
  }

defaultState ∷ State
defaultState =
  { homeDirectory: "/"
  , homeDirectoryError: Nothing
  , defaultTheme: Theme.Light
  }

type Message = Void

type ChildSlot = Unit

type HTML = H.ComponentHTML Query
type DSL = H.ComponentDSL State Query Message Slam

component ∷ H.Component HH.HTML Query Unit Message Slam
component =
  H.lifecycleComponent
    { initializer: Just (H.action Init)
    , finalizer: Nothing
    , render
    , eval
    , receiver: const Nothing
    , initialState: const defaultState
    }
    where
      render state =
        HH.form
          [ HP.class_ (HH.ClassName "sd-admin-ui-my-settings") ]
          (renderForm state)

      eval ∷ Query ~> DSL
      eval = case _ of
        Init next → do
          defaultTheme ← LS.retrieve (lmap show ∘ C.decode Theme.codec) LK.adminUIDefaultTheme
          homeDirectory ← LS.retrieve J.decodeJson LK.adminUIHomeDirectory
          for_ defaultTheme \theme →
            H.modify (_ { defaultTheme = theme })
          for_ homeDirectory \dir → do
            H.modify (_ { homeDirectory = dir })
          pure next
        DefaultThemeChanged newTheme next → do
          let t = unsafePartial fromJust (Theme.fromLabel newTheme)
          LS.persist (C.encode Theme.codec) LK.adminUIDefaultTheme t
          H.modify (_ { defaultTheme = t })
          changeTheme (Just t)
          pure next
        HomeDirectoryChanged newDirectory next → do
          -- We automatically append the trailing slash to make the UX a little
          -- nicer. This change does not get propagated to the UI as to not
          -- interrupt typing
          let directorified = fromMaybe newDirectory (String.stripSuffix (String.Pattern "/") newDirectory) <> "/"
          err ← validateHomeDirectory directorified
          case err of
            Just msg →
              H.modify ( _ { homeDirectoryError = Just msg })
            Nothing → do
              LS.persist J.encodeJson LK.adminUIHomeDirectory directorified
              H.modify (_ { homeDirectory = newDirectory, homeDirectoryError = Nothing })
          pure next

themes ∷ Array Theme
themes = [ Theme.Dark, Theme.Light ]

renderForm ∷ State → Array HTML
renderForm state =
  [ HH.fieldset
      [ HP.class_ (HH.ClassName "home-directory") ]
      $ [ HH.legend_ [ HH.text "Location of my home directory in the SlamData file system:" ]
        , HH.input
            [ HP.classes [ HH.ClassName "form-control" ]
            , HP.id_ "HomeDirectory"
            , HP.value state.homeDirectory
            , HE.onValueInput (HE.input HomeDirectoryChanged)
            ]
        ] <> maybe [] renderHomeDirectoryError state.homeDirectoryError
  , HH.fieldset
      [ HP.class_ (HH.ClassName "themes") ]
      [ HH.legend_ [ HH.text "Default theme for new decks:" ]
      , HH.p_ [ HH.text "This theme will also be used for the filesystem. You can change this setting on a deck by deck basis, by flipping the deck during editing." ]
      , HH.select
        [ HP.classes [ HH.ClassName "form-control" ]
        , HP.id_ "ThemeSelection"
          , HE.onValueChange (HE.input DefaultThemeChanged)
          , HP.value (Theme.toLabel state.defaultTheme)
          ]
          (themes <#> \t → HH.option_ [HH.text (Theme.toLabel t)])
      ]
  ]

renderHomeDirectoryError ∷ String → Array HTML
renderHomeDirectoryError msg =
  [ HH.div
      [ HP.classes [ CN.alert, CN.alertDanger, H.ClassName ("sd-dialog-error-box") ] ]
      [ HH.text msg ]
  ]

-- | Checks whether the input parses as a valid directory
validateHomeDirectory ∷ String → DSL (Maybe String)
validateHomeDirectory s =
  case parseAbsDir s >>= sandbox of
    Nothing →
      pure (Just "Please enter a directory path.")
    Just dir → do
      pure Nothing
