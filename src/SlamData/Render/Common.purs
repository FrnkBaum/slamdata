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

module SlamData.Render.Common
  ( row
  , content
  , fadeWhen
  , classedDiv
  , formGroup
  , clearFieldIcon
  , busyFieldIcon
  , svgElem
  , gripperGlobalNavNub
  , gripperDeckNavigation
  , gripperDeckMove
  , spinner
  ) where

import SlamData.Prelude

import Data.Array as Array
import Data.Int (toNumber)
import Data.String as String

import Halogen as H
import Halogen.HTML.Core (HTML, ClassName)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.HTML.Properties.ARIA as ARIA

import SlamData.Render.ClassName as CN
import SlamData.Render.Icon as I

row ∷ ∀ p f. Array (HTML p f) → HTML p f
row = HH.div [ HP.class_ $ H.ClassName "row" ]

content ∷ ∀ p f. Array (HTML p f) → HTML p f
content = HH.div [ HP.class_ CN.content ]

fadeWhen ∷ Boolean → Array ClassName
fadeWhen true = [ CN.fade ]
fadeWhen false = [ CN.fade, CN.in_ ]

classedDiv ∷ ∀ f p. ClassName → Array (HTML p (f Unit)) → HTML p (f Unit)
classedDiv cls = HH.div [ HP.classes [ cls ] ]

formGroup ∷ ∀ f p. Array (HTML p (f Unit)) → HTML p (f Unit)
formGroup = classedDiv CN.formGroup

clearFieldIcon ∷ ∀ f p. String → HTML p (f Unit)
clearFieldIcon label =
  HH.span
    [ HP.class_ (HH.ClassName "sd-clear-field-icon")
    , HP.title label
    , ARIA.label label
    ]
    [ I.removeSm
    , HH.span
        [ HP.class_ CN.srOnly ]
        [ HH.text label ]
    ]

busyFieldIcon ∷ ∀ f p. String → HTML p (f Unit)
busyFieldIcon label =
  HH.span
    [ HP.class_ (HH.ClassName "sd-busy-field")
    , HP.title label
    , ARIA.label label
    ]
    [ spinner
    , HH.span
        [ HP.class_ CN.srOnly ]
        [ HH.text label ]
    ]

svgElem ∷ ∀ r p i. HH.ElemName → Array (HP.IProp r i) → Array (HTML p i) → HTML p i
svgElem =
  HH.elementNS (HH.Namespace "http://www.w3.org/2000/svg")

data ViewBox = ViewBox Int Int Int Int

viewBoxToString ∷ ViewBox → String
viewBoxToString (ViewBox a b c d) =
  show a <> " " <> show b <> " " <> show c <> " " <> show d

gripperHelper ∷ ∀ p i. String → ViewBox → H.HTML p i
gripperHelper s vb =
  let
    xlinkAttr = HH.attrNS $ HH.Namespace "http://www.w3.org/1999/xlink"
    attr' = HH.AttrName >>> HP.attr
  in
    HH.span
      [ HP.class_ $ HH.ClassName $ "sd-gripper sd-gripper--" <> s
      , ARIA.hidden "true"
      ]
      [ svgElem (HH.ElemName "svg")
        [ attr' "preserveAspectRatio" "xMidYMid meet"
        , attr' "viewBox" $ viewBoxToString vb
        ]
        [ svgElem (HH.ElemName "use")
          [ xlinkAttr (HH.AttrName "xlink:href") $ "#sd-gripper--" <> s ]
          [ ]
        ]
      ]

gripperGlobalNavNub ∷ ∀ p i. H.HTML p i
gripperGlobalNavNub = gripperHelper "global-nav-nub" $ ViewBox 0 0 10 10

gripperDeckNavigation ∷ ∀ p i. H.HTML p i
gripperDeckNavigation = gripperHelper "deck-navigation" $ ViewBox 0 0 10 100

gripperDeckMove ∷ ∀ p i. H.HTML p i
gripperDeckMove = gripperHelper "deck-move" $ ViewBox 0 0 80 10

spinner ∷  ∀ p i. H.HTML p i
spinner =
  let
    circles = Array.range 0 7
    lcircles = toNumber $ Array.length circles
    animDur = 1.0  -- second
    deg x = show $ toNumber x * (360.0 / lcircles)

    anStyle i =
      String.joinWith ";"
        [ "-webkit-animation-duration:" <> d <> "s"
        , "animation-duration:" <> d <> "s"
        , "-webkit-animation-delay:" <> t <> "s"
        , "animation-delay:" <> t <> "s"
        ]
      where
      t = show $ (toNumber i - (lcircles - 1.0)) / lcircles * animDur
      d = show animDur

    circle i =
      svgElem (HH.ElemName "g")
        [ HP.attr (HH.AttrName "transform") $ "rotate(" <> deg i <> ") translate(34 0)" ]
        [ svgElem (HH.ElemName "circle")
            [ HP.attr (HH.AttrName "cx") "0"
            , HP.attr (HH.AttrName "cy") "0"
            , HP.attr (HH.AttrName "r") "6"
            , HP.attr (HH.AttrName "style") $ anStyle i
            ]
            [ ]
        ]
  in
    HH.div
      [ HP.class_ $ HH.ClassName "sd-spinner" ]
      [ svgElem (HH.ElemName "svg")
          [ HP.attr (HH.AttrName "viewBox") "0 0 100 100"
          , HP.attr (HH.AttrName "preserveAspectRatio") "xMidYMid"
          ]
          [ svgElem (HH.ElemName "g")
              [ HP.attr (HH.AttrName "transform") "translate(50 50)" ]
              $ map circle circles
          ]
      ]

