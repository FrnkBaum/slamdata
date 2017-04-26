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

module Test.StrongCheck.Data.Argonaut where

import Prelude
import Data.Argonaut.JCursor (JCursor)
import Data.Argonaut.JCursor.Gen (genJCursor)
import Data.Newtype (class Newtype, unwrap, wrap)
import Test.StrongCheck.Arbitrary (class Arbitrary)

newtype ArbJCursor = ArbJCursor JCursor

derive instance newtypeArbJCursor ∷ Newtype ArbJCursor _

instance arbitraryArbJCursor ∷ Arbitrary ArbJCursor where
  arbitrary = wrap <$> genJCursor

runArbJCursor ∷ ArbJCursor → JCursor
runArbJCursor = unwrap
