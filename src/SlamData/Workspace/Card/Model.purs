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

module SlamData.Workspace.Card.Model where

import SlamData.Prelude
import Data.Argonaut ((:=), (~>), (.?))
import Data.Argonaut as J
import Data.Codec.Argonaut as CA
import Data.Array as Array
import Data.List as L
import Data.Path.Pathy (fileName, runFileName)
import Data.Rational ((%))
import Data.StrMap as StrMap
import Data.Variant (on)

import SlamData.Workspace.Card.Ace.Model as Ace
import SlamData.Workspace.Card.CardType as CT
import SlamData.Workspace.Card.CardType.Ace as CTA
import SlamData.Workspace.Card.DownloadOptions.Component.State as DLO
import SlamData.Workspace.Card.Draftboard.Layout as Layout
import SlamData.Workspace.Card.Draftboard.Model as DB
import SlamData.Workspace.Card.Draftboard.Orientation as Orn
import SlamData.Workspace.Card.Draftboard.Pane as Pane
import SlamData.Workspace.Card.Markdown.Model as MD
import SlamData.Workspace.Card.Open.Model as Open
import SlamData.Workspace.Card.Port as Port
import SlamData.Workspace.Card.Query.Model as Query
import SlamData.Workspace.Card.Setups.Viz.Model as SetupViz
import SlamData.Workspace.Card.StructureEditor.Model as StructureEditor
import SlamData.Workspace.Card.Table.Model as JT
import SlamData.Workspace.Card.Tabs.Model as Tabs
import SlamData.Workspace.Card.Variables.Model as Variables
import SlamData.Workspace.Card.Viz.Model as Viz
import SlamData.Workspace.Deck.DeckId (DeckId)

import Test.StrongCheck.Arbitrary as SC
import Test.StrongCheck.Gen as Gen

import Utils (decodec)

data AnyCardModel
  = Ace (CT.Ace ()) Ace.Model
  | Search String
  | Markdown MD.Model
  | Table JT.Model
  | Download
  | Variables Variables.Model
  | Troubleshoot
  | Cache (Maybe String)
  | Open Open.Model
  | DownloadOptions DLO.State
  | Draftboard DB.Model
  | Tabs Tabs.Model
  | StructureEditor StructureEditor.Model
  | Viz Viz.Model
  | SetupViz SetupViz.Model

instance arbitraryAnyCardModel ∷ SC.Arbitrary AnyCardModel where
  arbitrary =
    Gen.oneOf (pure Download)
      [ Ace <$> Gen.allInArray CTA.all <*> Ace.genModel
      , Search <$> SC.arbitrary
      , Markdown <$> MD.genModel
      , Table <$> JT.genModel
      , Variables <$> Variables.genModel
      , pure Troubleshoot
      , Cache <$> SC.arbitrary
      , Open <$> SC.arbitrary
      , Draftboard <$> DB.genModel
      , Tabs <$> Tabs.genModel
      , StructureEditor <$> StructureEditor.genModel
      , Viz <$> Viz.gen
      , SetupViz <$> SetupViz.gen
      ]

updateCardModel ∷ AnyCardModel → AnyCardModel → AnyCardModel
updateCardModel = case _, _ of
  Markdown author, Markdown consumer →
    Markdown $ StrMap.union author consumer
  Search _, Search consumer →
    Search consumer
  Viz _, Viz consumer →
    Viz consumer
  author, _ →
    author

instance eqAnyCardModel ∷ Eq AnyCardModel where
  eq = case _, _ of
    Ace x1 y1, Ace x2 y2 → CT.eq_ (expand x1) (expand x2) && Ace.eqModel y1 y2
    Search s1, Search s2 → s1 ≡ s2
    Markdown x, Markdown y → x ≡ y
    Table x, Table y → JT.eqModel x y
    Download, Download → true
    Variables x, Variables y → Variables.eqModel x y
    Troubleshoot, Troubleshoot → true
    Cache x, Cache y → x ≡ y
    Open x, Open y → x ≡ y
    DownloadOptions x, DownloadOptions y → DLO.eqState x y
    Draftboard x, Draftboard y → DB.eqModel x y
    Tabs x, Tabs y → Tabs.eqModel x y
    StructureEditor x, StructureEditor y → x == y
    SetupViz x, SetupViz y → SetupViz.eq_ x y
    Viz x, Viz y → Viz.eq_ x y
    _, _ → false

instance encodeJsonCardModel ∷ J.EncodeJson AnyCardModel where
  encodeJson = encode

instance decodeJsonCardModel ∷ J.DecodeJson AnyCardModel where
  decodeJson = decode

modelCardType ∷ AnyCardModel → CT.CardType
modelCardType = case _ of
  Ace mode _ → expand mode
  Search _ → CT.search
  Markdown _ → CT.markdown
  Table _ → CT.table
  Download → CT.download
  Variables _ → CT.variables
  Troubleshoot → CT.troubleshoot
  Cache _ → CT.cache
  Open _ → CT.open
  DownloadOptions _ → CT.downloadOptions
  Draftboard _ → CT.draftboard
  Tabs _ → CT.tabs
  StructureEditor _ → CT.structureEditor
  SetupViz _ → CT.setupViz
  Viz _ → CT.viz

encode ∷ AnyCardModel → J.Json
encode card =
  "cardType" := (CT.encode $ modelCardType card)
    ~> "model" := encodeCardModel card
    ~> J.jsonEmptyObject

decode ∷ J.Json → Either String AnyCardModel
decode js = do
  obj ← J.decodeJson js
  cardType ← CT.decode =<< obj .? "cardType"
  model ← obj .? "model"
  decodeCardModel model cardType

encodeCardModel ∷ AnyCardModel → J.Json
encodeCardModel = case _ of
  Ace mode model → Ace.encode model
  Search txt → J.encodeJson txt
  Markdown model → MD.encode model
  Table model → CA.encode JT.codec model
  Download → J.jsonEmptyObject
  Variables model → Variables.encode model
  Troubleshoot → J.jsonEmptyObject
  Cache model → J.encodeJson model
  Open res → Open.encode res
  DownloadOptions model → CA.encode DLO.codec model
  Draftboard model → DB.encode model
  Tabs model → CA.encode Tabs.codec model
  StructureEditor model → StructureEditor.encode model
  SetupViz model → CA.encode SetupViz.codec model
  Viz model → CA.encode Viz.codec model

decodeCardModel
  ∷ J.Json
  → CT.CardType
  → String ⊹ AnyCardModel
decodeCardModel js = case_
  # on CT._aceSql (const $ map (Ace CT.aceSql) $ Ace.decode js)
  # on CT._aceMarkdown (const $ map (Ace CT.aceMarkdown) $ Ace.decode js)
  # on CT._search (const $ map Search $ J.decodeJson js)
  # on CT._markdown (const $ map Markdown $ MD.decode js)
  # on CT._table (const $ map Table $ decodec JT.codec js)
  # on CT._download (const $ pure Download)
  # on CT._variables (const $ map Variables $ Variables.decode js)
  # on CT._troubleshoot (const $ pure Troubleshoot)
  # on CT._cache (const $ map Cache $ J.decodeJson js)
  # on CT._open (const $ map Open $ decodeOpen js)
  # on CT._downloadOptions (const $ map DownloadOptions $ decodec DLO.codec js)
  # on CT._draftboard (const $ map Draftboard $ DB.decode js)
  # on CT._tabs (const $ map Tabs $ decodec Tabs.codec js)
  # on CT._structureEditor (const $ map StructureEditor $ StructureEditor.decode js)
  # on CT._setupViz (const $ map SetupViz $ decodec SetupViz.codec js)
  # on CT._viz (const $ map Viz $ decodec Viz.codec js)
  where
  -- For backwards compat
  decodeOpen j =
    Open.decode j <|> (map Open.Resource <$> J.decodeJson j)

cardModelOfType ∷ Port.Out → CT.CardType → AnyCardModel
cardModelOfType (port × varMap) = case_
  # on CT._aceSql (const $ Ace CT.aceSql $ Query.initialModel port)
  # on CT._aceMarkdown (const $ Ace CT.aceMarkdown Ace.emptyModel)
  # on CT._search (const $ Search "")
  # on CT._markdown (const $ Markdown MD.emptyModel)
  # on CT._table (const $ Table JT.emptyModel)
  # on CT._download (const Download)
  # on CT._variables (const $ Variables Variables.emptyModel)
  # on CT._troubleshoot (const Troubleshoot)
  # on CT._cache (const $ Cache Nothing)
  # on CT._open (const $ Open Nothing)
  # on CT._downloadOptions
      (const $ DownloadOptions $ DLO.initialState
       { targetName = runFileName ∘ fileName <$> Port.extractFilePath varMap })
  # on CT._draftboard (const $ Draftboard DB.emptyModel)
  # on CT._tabs (const $ Tabs Tabs.initialModel)
  # on CT._structureEditor (const $ StructureEditor StructureEditor.initialModel)
  # on CT._setupViz (const $ SetupViz SetupViz.initial)
  # on CT._viz (const $ Viz Viz.initial)


singletonDraftboard ∷ DeckId → AnyCardModel
singletonDraftboard deckId =
  Draftboard { layout: Pane.Cell (Just deckId) }

singletonTabs ∷ DeckId → AnyCardModel
singletonTabs deckId =
  Tabs { tabs: pure deckId }

splitDraftboard ∷ Orn.Orientation → L.List DeckId → AnyCardModel
splitDraftboard orn deckIds =
  Draftboard { layout: Pane.Split orn (mkCell <$> deckIds) }
  where
    size =
      L.length deckIds

    mkCell deckId =
      (1 % size) × Pane.wrap (Orn.reverse orn) (Pane.Cell (Just deckId))

mirrorInParent ∷ DeckId → DeckId → AnyCardModel → Maybe AnyCardModel
mirrorInParent oldId newId = case _ of
  Draftboard { layout } → do
    cursor ← Pane.getCursorFor (Just oldId) layout
    let
      cursor' = fromMaybe L.Nil (L.tail cursor)
      orn = case Pane.getAt cursor' layout of
        Just (Pane.Split o _) → o
        _ → Orn.Vertical
    layout' ←
      Layout.insertSplit
        (Pane.Cell (Just newId)) orn (1 % 2) Layout.SideB cursor' layout
    pure (Draftboard { layout: layout' })
  Tabs { tabs } →
    let
      tabs' = do
        deckId ← tabs
        if deckId ≡ oldId
          then [ deckId, newId ]
          else [ deckId ]
    in
      pure (Tabs { tabs: tabs' })
  _ → Nothing

childDeckIds ∷ AnyCardModel → L.List DeckId
childDeckIds = case _ of
  Draftboard { layout } → L.catMaybes (L.fromFoldable layout)
  Tabs { tabs } → L.fromFoldable tabs
  s → mempty

updatePointer
  ∷ DeckId
  → Maybe DeckId
  → AnyCardModel
  → AnyCardModel
updatePointer old new = case _ of
  Draftboard { layout } →
    Draftboard { layout: update <$> layout}
  Tabs { tabs } →
    Tabs { tabs: Array.mapMaybe (update ∘ Just) tabs }
  card → card

  where
    update (Just deckId) | deckId ≡ old = new
    update a = a
