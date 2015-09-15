{-
Copyright 2015 SlamData, Inc.

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

module Test.Selenium.ActionSequence
  ( selectAll
  , copy
  , paste
  , undo
  , sendDelete
  , sendEnter
  ) where

import Prelude

import Data.Char (fromCharCode)
import Data.Foldable (traverse_)
import Data.String (fromChar)
import Selenium.ActionSequence hiding (sequence)
import Selenium.Types (ControlKey())

selectAll :: ControlKey -> Sequence Unit
selectAll modifierKey = sendKeyCombo [modifierKey] "a"

copy :: ControlKey -> Sequence Unit
copy modifierKey = sendKeyCombo [modifierKey] "c"

paste :: ControlKey -> Sequence Unit
paste modifierKey = sendKeyCombo [modifierKey] "v"

undo :: ControlKey -> Sequence Unit
undo modifierKey = sendKeyCombo [modifierKey] "z"

sendDelete :: Sequence Unit
sendDelete = sendKeys $ fromChar $ fromCharCode 57367

sendEnter :: Sequence Unit
sendEnter = sendKeys $ fromChar $ fromCharCode 13

sendKeyCombo :: Array ControlKey -> String -> Sequence Unit
sendKeyCombo ctrlKeys str = do
  traverse_ keyDown ctrlKeys
  sendKeys str
  traverse_ keyUp ctrlKeys
