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

module SlamData.Workspace.Card.Geo.Model where

import SlamData.Prelude

import Data.Argonaut as J
import Data.Argonaut ((~>), (:=), (.?))
import Data.Char.Gen (genAlphaLowercase)
import Data.String.Gen (genString)
import Data.Path.Pathy as Pt
import Data.URI (URIRef)
import Data.URI as URI
import Global (encodeURIComponent, decodeURIComponent)

import Test.StrongCheck.Arbitrary (arbitrary)
import Test.StrongCheck.Gen as Gen

type ModelR =
  { osmURI ∷ URIRef -- | Open Street Map tile layer URI
  , view ∷ { lat ∷ Number, lng ∷ Number }
  , zoom ∷ Int
  }

type Model = Maybe ModelR

initialModel ∷ Model
initialModel = Nothing

eqR ∷ ModelR → ModelR → Boolean
eqR r1 r2 =
  r1.osmURI ≡ r2.osmURI
  && r1.view.lat ≡ r2.view.lat
  && r1.view.lng ≡ r2.view.lng
  && r1.zoom ≡ r2.zoom

eqModel ∷ Model → Model → Boolean
eqModel Nothing Nothing = true
eqModel (Just r1) (Just r2) = eqR r1 r2
eqModel _ _ = false


-- Applies the given function to every `String` in `Either URI RelativeRef`.
-- This is needed here to encode and decode `OSMURIRef`s as they are templates containing `{` and `}`.
onURIRef ∷ (String → String) → URIRef → URIRef
onURIRef f = case _ of
  Left uri → Left $ onURI f uri
  Right ref → Right $ onRef f ref
  where
  onURI fn (URI.URI mbScheme hPart mQuery mFragment) = URI.URI
    (onScheme fn <$> mbScheme)
    (onHPart fn hPart)
    (onQuery fn <$> mQuery)
    (onFragment fn <$> mFragment)

  onRef fn (URI.RelativeRef rPart mQuery mFragment) = URI.RelativeRef
    (onRPart fn rPart)
    (onQuery fn <$> mQuery)
    (onFragment fn <$> mFragment)

  onScheme fn (URI.URIScheme s) = URI.URIScheme $ fn s

  onHPart fn (URI.HierarchicalPart mAuthority mURIPathAbs) = URI.HierarchicalPart
    (onAuthority fn <$> mAuthority)
    (onURIPathAbs fn <$> mURIPathAbs)

  onQuery fn (URI.Query lst) = URI.Query $ onPair fn <$> lst

  onPair fn (k × mv) = fn k × map fn mv

  onFragment fn s = fn s

  onRPart fn (URI.RelativePart mAuthority mURIPathRel) = URI.RelativePart
    (onAuthority fn <$> mAuthority)
    (onURIPathRel fn <$> mURIPathRel)

  onAuthority fn (URI.Authority mUserInfo hosts) = URI.Authority
    (onUserInfo fn <$> mUserInfo)
    (onHostPair fn <$> hosts)

  onHostPair fn (host × mport) =
    onHost fn host × mport

  onURIPathAbs fn p = bimap (onPath fn) (onPath fn) p

  onURIPathRel fn p = bimap (onPath fn) (onPath fn) p

  onPath ∷ ∀ a b c. (String → String) → Pt.Path a b c → Pt.Path a b c
  onPath fn = Pt.refine (Pt.FileName ∘ fn ∘ Pt.runFileName) (Pt.DirName ∘ fn ∘ Pt.runDirName)

  onUserInfo fn s = fn s

  onHost fn = case _ of
    URI.IPv6Address s → URI.IPv6Address $ fn s
    URI.IPv4Address s → URI.IPv4Address $ fn s
    URI.NameAddress s → URI.NameAddress $ fn s



genModel ∷ Gen.Gen Model
genModel = do
  isNothing ← arbitrary
  if isNothing
    then pure Nothing
    else map Just do
    scheme ← append "a" <$> genString genAlphaLowercase
    address ← append "a" <$> genString genAlphaLowercase
    zoom ← arbitrary
    lat ← arbitrary
    lng ← arbitrary
    pure
      { osmURI: Left $ URI.URI
        (Just $ URI.URIScheme scheme)
        (URI.HierarchicalPart
         (Just $ URI.Authority Nothing [(URI.NameAddress address) × Nothing ])
         Nothing)
        Nothing
        Nothing
      , zoom
      , view: {lat, lng}
      }

encode ∷ Model → J.Json
encode Nothing = J.jsonNull
encode (Just r) =
  "configType" := "show-geo-chart"
  ~> "osmURI" := (URI.printURIRef $ onURIRef encodeURIComponent r.osmURI)
  ~> "viewLat" := r.view.lat
  ~> "viewLng" := r.view.lng
  ~> "zoom" := r.zoom
  ~> J.jsonEmptyObject

decode ∷ J.Json → String ⊹ Model
decode js
  | J.isNull js = pure Nothing
  | otherwise = map Just $ decode' js
  where
  decode' ∷ J.Json → String ⊹ ModelR
  decode' js' = do
    obj ← J.decodeJson js'
    configType ← obj .? "configType"
    unless (configType ≡ "show-geo-chart")
      $ throwError "This is not show geo chart model"
    osmURIStr ← obj .? "osmURI"
    osmURI ← map (onURIRef decodeURIComponent) $ lmap show $ URI.runParseURIRef $ osmURIStr
    zoom ← obj .? "zoom"
    lat ← obj .? "viewLat"
    lng ← obj .? "viewLng"
    pure { osmURI
         , zoom
         , view: { lat, lng }
         }
