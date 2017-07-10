module SlamData.Workspace.Card.Setups.Auxiliary.Piece where

import SlamData.Prelude

import Data.Argonaut as J
import Data.Argonaut ((~>), (:=), (.?))
import Data.Char.Gen (genAlphaLowercase)
import Data.Path.Pathy ((</>), (<.>), file, rootDir, dir)
import Data.String.Gen (genString)
import Data.URI (URIRef)
import Data.URI as URI

import Global (encodeURIComponent, decodeURIComponent)

import SlamData.Common.Sort (Sort(..))
import SlamData.Common.Align (Align(..))
import SlamData.Workspace.Card.Setups.Chart.ColorScheme (ColorScheme(..))
import SlamData.Workspace.Card.Geo.Model (onURIRef)

import Test.StrongCheck.Arbitrary (arbitrary)
import Test.StrongCheck.Gen as Gen

type OsmURI =
  { uri ∷ URIRef
  , string ∷ String
  }

type MinMax =
  { min ∷ Number
  , max ∷ Number
  }

minSize ∷ Number
minSize = 10.0

maxSize ∷ Number
maxSize = 50.0

isSmooth ∷ Boolean
isSmooth = false

isStacked ∷ Boolean
isStacked = false

size ∷ Number
size = 10.0

axisLabelAngle ∷ Number
axisLabelAngle = 0.0

circular ∷ Boolean
circular = false

isColorSchemeReversed ∷ Boolean
isColorSchemeReversed = false

colorScheme ∷ ColorScheme
colorScheme = RedToBlue

order ∷ Sort
order = Asc

align ∷ Align
align = LeftAlign

minValue ∷ Number
minValue = 1.0

maxValue ∷ Number
maxValue = 50.0

optionalMarkers ∷ Boolean
optionalMarkers = false

osmURI ∷ URIRef
osmURI =
  Left $ URI.URI
  (Just $ URI.URIScheme "http")
  (URI.HierarchicalPart
   (Just $ URI.Authority Nothing [(URI.NameAddress "{s}.tile.osm.org") × Nothing])
   (Just $ Right $ rootDir </> dir "{z}" </> dir "{x}" </> file "{y}" <.> "png"))
  Nothing
  Nothing

osm ∷ OsmURI
osm = { uri: osmURI, string: URI.printURIRef osmURI }

genOsm ∷ Gen.Gen OsmURI
genOsm = do
  scheme ← append "a" <$> genString genAlphaLowercase
  address ← append "a" <$> genString genAlphaLowercase
  let
    uri =
      Left $ URI.URI
      (Just $ URI.URIScheme $ scheme)
      (URI.HierarchicalPart
       (Just $ URI.Authority Nothing [(URI.NameAddress address) × Nothing ])
       Nothing)
      Nothing
      Nothing
    string = URI.printURIRef uri
  pure { uri, string }

genMinMax ∷ Gen.Gen MinMax
genMinMax = do
  { min: _, max: _ } <$> arbitrary <*> arbitrary

encodeOsmURI ∷ OsmURI → J.Json
encodeOsmURI {uri} = J.encodeJson $ URI.printURIRef $ onURIRef encodeURIComponent uri

decodeOsmURI ∷ J.Json → String ⊹ OsmURI
decodeOsmURI j = do
  string ← J.decodeJson j
  uri ←
    map (onURIRef decodeURIComponent)
    $ lmap (\x → show x <> ":" <> string)
    $ URI.runParseURIRef string
  pure { uri, string }

encodeMinMax ∷ MinMax → J.Json
encodeMinMax {min, max} =
  "min" := min
  ~> "max" := max
  ~> J.jsonEmptyObject

decodeMinMax ∷ J.Json → String ⊹ MinMax
decodeMinMax = J.decodeJson >=> \obj → do
  min ← obj .? "min"
  max ← obj .? "max"
  pure { min, max }
