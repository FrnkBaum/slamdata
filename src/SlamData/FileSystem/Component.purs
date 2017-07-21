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

module SlamData.FileSystem.Component
  ( module SlamData.FileSystem.Component.State
  , module SlamData.FileSystem.Component.Query
  , module SlamData.FileSystem.Component.ChildSlot
  , component
  ) where

import SlamData.Prelude

import CSS as CSS
import Control.Monad.Aff.AVar as AVar
import Control.Monad.Fork (fork)
import Control.Monad.Rec.Class (tailRecM, Step(Done, Loop))
import Control.UI.Browser as Browser
import Control.UI.Browser.Event as Be
import Control.UI.File as Cf
import DOM.Event.Event as DEE
import Data.Argonaut as J
import Data.Array as Array
import Data.Coyoneda (liftCoyoneda)
import Data.Foldable as F
import Data.Lens ((.~), preview)
import Data.MediaType (MediaType(..))
import Data.MediaType.Common (textCSV, applicationJSON)
import Data.Path.Pathy (rootDir, (</>), dir, file, parentDir, printPath)
import Data.String as S
import Data.String.Regex as RX
import Data.String.Regex.Flags as RXF
import Halogen as H
import Halogen.Component.Utils (busEventSource)
import Halogen.HTML as HH
import Halogen.HTML.CSS as HCSS
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.EventSource as ES
import Quasar.Advanced.QuasarAF as QA
import Quasar.Advanced.Types as QAT
import Quasar.Data (QData(..))
import Quasar.Error as QE
import SlamData.AdminUI.Component as AdminUI
import SlamData.AdminUI.Types as AdminUI.Types
import SlamData.Common.Sort (notSort)
import SlamData.Config as Config
import SlamData.Download.Model as DM
import SlamData.Dialog.Component as NewDialog
import SlamData.Dialog.Render as RenderDialog
import SlamData.FileSystem.Breadcrumbs.Component as Breadcrumbs
import SlamData.FileSystem.Component.CSS as FileSystemClassNames
import SlamData.FileSystem.Component.ChildSlot (ChildQuery, ChildSlot)
import SlamData.FileSystem.Component.ChildSlot as CS
import SlamData.FileSystem.Component.Query (Query(..))
import SlamData.FileSystem.Component.Render (sorting, toolbar)
import SlamData.FileSystem.Component.State (State, initialState)
import SlamData.FileSystem.Component.State as State
import SlamData.FileSystem.Dialog as DialogT
import SlamData.FileSystem.Dialog.Component as Dialog
import SlamData.FileSystem.Dialog.Component.Message as DialogMessage
import SlamData.FileSystem.Dialog.Mount.Component as Mount
import SlamData.FileSystem.Listing.Component as Listing
import SlamData.FileSystem.Listing.Item (Item(..), itemResource, sortItem)
import SlamData.FileSystem.Listing.Item.Component as Item
import SlamData.FileSystem.Resource (Resource)
import SlamData.FileSystem.Resource as R
import SlamData.FileSystem.Routing (browseURL)
import SlamData.FileSystem.Routing.Salt (newSalt)
import SlamData.FileSystem.Search.Component as Search
import SlamData.GlobalError as GE
import SlamData.GlobalMenu.Component as GlobalMenu
import SlamData.Header.Component as Header
import SlamData.Header.Gripper.Component as Gripper
import SlamData.LocalStorage.Class as LS
import SlamData.LocalStorage.Keys as LSK
import SlamData.Monad (Slam)
import SlamData.Monad.License (notifyDaysRemainingIfNeeded)
import SlamData.Notification.Component as NC
import SlamData.Quasar (ldJSON) as API
import SlamData.Quasar.Auth (authHeaders) as API
import SlamData.Quasar.Class (liftQuasar)
import SlamData.Quasar.Data (makeFile, save) as API
import SlamData.Quasar.FS (children, delete, getNewName) as API
import SlamData.Quasar.Mount (mountInfo, saveMount) as API
import SlamData.Render.ClassName as CN
import SlamData.Render.Common (content, row)
import SlamData.Wiring as Wiring
import SlamData.Workspace.Action (Action(..), AccessType(..))
import SlamData.Workspace.Routing (mkWorkspaceURL)
import Utils (finally)
import Utils.DOM as DOM
import Utils.Path (DirPath, getNameStr)

type HTML = H.ParentHTML Query ChildQuery ChildSlot Slam
type DSL = H.ParentDSL State Query ChildQuery ChildSlot Void Slam

component ∷ H.Component HH.HTML Query Unit Void Slam
component =
  H.lifecycleParentComponent
    { render
    , eval
    , receiver: const Nothing
    , initialState: const initialState
    , initializer: Just (H.action Init)
    , finalizer: Nothing
    }

render ∷ State → HTML
render state@{ version, sort, salt, path } =
  HH.div
    [ HP.classes [ FileSystemClassNames.filesystem ]
    , HE.onClick (HE.input_ DismissSignInSubmenu)
    ]
    $ [ HH.slot' CS.cpHeader unit Header.component unit $ HE.input HandleHeader
      , content
          [ HH.slot' CS.cpSearch unit Search.component unit $ HE.input HandleSearch
          , HH.div_
            [ Breadcrumbs.render { path, sort, salt }
            , toolbar state
            ]
          , row [ sorting state ]
          , HH.slot' CS.cpListing unit Listing.component unit $ HE.input HandleListing
          ]
      , HH.slot' CS.cpDialog unit Dialog.component unit $ HE.input HandleDialog
      , HH.slot' CS.cpNewDialog unit (NewDialog.component DialogT.dialog) state.dialog $ HE.input HandleNewDialog
      , HH.slot' CS.cpNotify unit (NC.component NC.Hidden) unit
          $ HE.input HandleNotifications
      , HH.slot' CS.cpAdminUI unit AdminUI.component unit $ HE.input HandleAdminUI
      ]
    <> (guard state.presentIntroVideo $> renderIntroVideo)

renderIntroVideo ∷ HTML
renderIntroVideo =
  HH.div
    [ HP.class_ CN.dialogContainer
    , HE.onClick $ HE.input DismissIntroVideoBackdrop
    ]
    [ HH.div
        [ HP.class_ CN.dialog
        , HCSS.style do
             CSS.paddingLeft CSS.nil
             CSS.paddingRight CSS.nil
        ]
        [ HH.h4
            [ HCSS.style do
                CSS.paddingLeft $ CSS.rem 1.0
                CSS.paddingRight $ CSS.rem 1.0
            ]
            [ HH.text "Welcome to SlamData!" ]
        , HH.video
            [ HP.autoplay true ]
            [ HH.source
                [ HP.type_ (MediaType "video/mp4")
                , HP.src "video/getting-started.mp4"
                ]
            ]
        , RenderDialog.modalFooter
            [ HH.button
                [ HP.type_ HP.ButtonButton
                , HE.onClick $ HE.input_ DismissIntroVideo
                , HP.classes [ HH.ClassName "btn", HH.ClassName "btn-primary" ]
                , HCSS.style $ CSS.marginRight $ CSS.rem 1.0
                ]
                [ HH.text "Skip video" ]
            ]
        ]
    ]

eval ∷ Query ~> DSL
eval = case _ of
  Init next → do
    w ← Wiring.expose
    dismissedIntroVideoBefore >>= if _
      then
        void $ H.query' CS.cpNotify unit $ H.action $ NC.UpdateRenderMode NC.Notifications
      else
        void $ fork $ liftQuasar QA.licenseInfo >>= case _ of
          Right { status: QAT.LicenseValid } →
            H.modify $ State._presentIntroVideo .~ true
          Right { status: QAT.LicenseExpired } →
            pure unit
          Left _ →
            liftQuasar QA.serverInfo >>= traverse_
              (_.name >>> eq "Quasar-Advanced" >>> not >>> flip when (H.modify $ State._presentIntroVideo .~ true))
    H.subscribe $ busEventSource (flip HandleError ES.Listening) w.bus.globalError
    H.subscribe $ busEventSource (flip HandleSignInMessage ES.Listening) w.auth.signIn
    H.subscribe $ busEventSource (flip HandleLicenseProblem ES.Listening) w.bus.licenseProblems
    notifyDaysRemainingIfNeeded
    pure next
  Transition page next → do
    H.modify
      $ (State._isMount .~ page.isMount)
      ∘ (State._salt .~ page.salt)
      ∘ (State._sort .~ page.sort)
      ∘ (State._path .~ page.path)
    _ ← H.query' CS.cpListing unit $ H.action $ Listing.Reset
    _ ← H.query' CS.cpSearch unit $ H.action $ Search.SetLoading true
    _ ← H.query' CS.cpSearch unit $ H.action $ Search.SetValue $ fromMaybe "" page.query
    _ ← H.query' CS.cpSearch unit $ H.action $ Search.SetValid true
    _ ← H.query' CS.cpSearch unit $ H.action $ Search.SetPath page.path
    resort
    pure next

  PreventDefault e q → do
    H.liftEff $ DEE.preventDefault e
    eval q
  Resort next → do
    st ← H.get
    searchValue ← H.query' CS.cpSearch unit (H.request Search.GetValue)
    H.liftEff $ Browser.setLocation $ browseURL searchValue (notSort st.sort) st.salt st.path
    pure next
  SetPath path next → do
    H.modify $ State._path .~ path
    pure next
  SetSort sort next → do
    H.modify $ State._sort .~ sort
    resort
    pure next
  SetSalt salt next → do
    H.modify $ State._salt .~ salt
    pure next
  CheckIsMount path next → do
    checkIsMount path
    pure next
  CheckIsUnconfigured next → do
    checkIsUnconfigured
    pure next
  SetVersion version next → do
    H.modify $ State._version .~ Just version
    pure next

  ShowHiddenFiles next → do
    H.modify $ State._showHiddenFiles .~ true
    _ ← H.query' CS.cpListing unit $ H.action $ Listing.SetIsHidden false
    pure next
  HideHiddenFiles next → do
    H.modify $ State._showHiddenFiles .~ false
    _ ← H.query' CS.cpListing unit $ H.action $ Listing.SetIsHidden true
    pure next

  Configure next → do
    path ← H.gets _.path
    configure $ R.Database path
    pure next
  MakeMount next → do
    parent ← H.gets _.path
    showDialogNew $ DialogT.Mount $ Mount.New { parent }
    pure next
  MakeFolder next → do
    result ← runExceptT do
      path ← lift $ H.gets _.path
      dirName ← ExceptT $ API.getNewName path Config.newFolderName
      let
        dirPath = path </> dir dirName
        dirRes = R.Directory dirPath
        dirItem = PhantomItem dirRes
        hiddenFile = dirPath </> file (Config.folderMark)
        cleanupItem = void $ H.lift $ H.query' CS.cpListing unit $ H.action $ Listing.Filter (_ ≠ dirItem)
      _ ← H.lift $ H.query' CS.cpListing unit $ H.action $ Listing.Add dirItem
      finally cleanupItem $ ExceptT $ API.save hiddenFile J.jsonEmptyObject
      pure dirRes
    case result of
      Left err → case GE.fromQError err of
        Left msg →
          showDialogNew $ DialogT.Error
            $ "You can only create files or folders in data sources."
            ⊕ "Please mount a data source, and then create your file or location inside the mounted data source."
        Right ge →
          GE.raiseGlobalError ge
      Right dirRes →
        void $ H.query' CS.cpListing unit $ H.action $ Listing.Add $ Item dirRes
    pure next
  MakeWorkspace next → do
    state ← H.get
    isMounted >>= if _
       then
         createWorkspace state.path \mkUrl →
           H.liftEff $ Browser.setLocation $ mkUrl New
       else
         showDialogNew
           $ DialogT.Error
           $ "There was a problem creating the workspace: Path "
           ⊕ printPath state.path
           ⊕ " is not inside a mount."
    pure next
  UploadFile el next → do
    mbInput ← H.liftEff $ DOM.querySelector "input" el
    for_ mbInput \input →
      void $ H.liftEff $ Be.raiseEvent "click" input
    pure next
  FileListChanged el next → do
    fileArr ← map Cf.fileListToArray $ (H.liftAff $ Cf.files el)
    H.liftEff $ Browser.clearValue el
    -- TODO: notification? this shouldn't be a runtime exception anyway!
    -- let err ∷ Slam Unit
    --     err = throwError $ error "empty filelist"
    -- in H.liftAff err
    for_ (Array.head fileArr) uploadFileSelected
    pure next
  Download next → do
    showDialogNew ∘ DialogT.Download ∘ R.Directory =<< H.gets _.path
    pure next
  DismissSignInSubmenu next → do
    dismissSignInSubmenu
    pure next
  DismissMountHint next → do
    dismissMountHint
    pure next
  DismissIntroVideo next → do
    dismissIntroVideo
    pure next
  DismissIntroVideoBackdrop me next → do
    isDialog ← H.liftEff $ DOM.nodeEq (DOM.target me) (DOM.currentTarget me)
    when isDialog do
      dismissIntroVideo
    pure next
  HandleError ge next → do
    showDialogNew $ DialogT.Error $ GE.print ge
    pure next
  HandleListing (Listing.ItemMessage m) next → do
    handleItemMessage m
    pure next
  HandleListing (Listing.Added items) next
    | Array.length items < 2 → do
        resort
        pure next
    | otherwise → do
        path ← H.gets _.path
        presentMountHint items path
        resort
        pure next
  HandleDialog DialogMessage.Dismiss next →
    pure next
  -- HandleDialog (DialogMessage.MountSave originalMount) next → do
  --   mbMbMount ←
  --     -- eval (Save k) = do
  --     --   { new, parent, name } ← H.get
  --     --   let name' = fromMaybe "" name
  --     --   let parent' = fromMaybe rootDir parent
  --     --   newName ←
  --     --     if new then Api.getNewName parent' name' else pure (pure name')
  --     --   case newName of
  --     --     Left err → do
  --     --       handleQError err
  --     --       pure $ k Nothing
  --     --     Right newName' → do
  --     --       result ← querySettings (H.request (SQ.Submit parent' newName'))
  --     --       mount ← case result of
  --     --         Just (Right m) → pure (Just m)
  --     --         Just (Left err) → do
  --     --           handleQError err
  --     --           pure Nothing
  --     --         Nothing → pure Nothing
  --     --       H.modify (MCS._saving .~ false)
  --     --       pure $ k mount
  --     H.query' CS.cpDialog unit $ H.request Dialog.SaveMount
  --   for_ (join mbMbMount) \newPath → do
  --     hideDialog
  --     path ← H.gets _.path
  --     case originalMount of
  --       -- Refresh if mount is current directory
  --       -- path </> dir "" is equal to path
  --       Nothing | R.Database path ≡ newPath || (R.Database $ path </> dir "") ≡ newPath →
  --         H.liftEff Browser.reload
  --       -- Add new item to list
  --       Nothing →
  --         void $ H.query' CS.cpListing unit $ H.action $ Listing.Add $ Item (R.Mount newPath)
  --       -- Rename current mount at path
  --       Just oldPath@(R.Database p) | path ≡ p && oldPath /= newPath → do
  --         handleItemMessage (Item.Open $ R.Mount newPath)
  --         void $ API.delete (R.Mount oldPath)
  --       -- Rename mount in listing
  --       Just oldPath | oldPath /= newPath → do
  --         _ ← H.query' CS.cpListing unit $ H.action $ Listing.Remove $ Item (R.Mount oldPath)
  --         _ ← H.query' CS.cpListing unit $ H.action $ Listing.Add $ Item (R.Mount newPath)
  --         void $ API.delete (R.Mount oldPath)
  --       Just oldPath → do
  --         pure unit
  --   resort
  --   checkIsMount =<< H.gets _.path
  --   checkIsUnconfigured
  --   pure next
  -- HandleDialog DialogMessage.MountDelete next → do
  --   mount ← R.Mount ∘ R.Database <$> H.gets _.path
  --   remove mount
  --   H.liftEff Browser.reload
  --   pure next
  HandleNewDialog (NewDialog.Confirm act) next → do
    case act of
      DialogT.DoDelete res → do
        remove res
        hideDialogNew
      DialogT.DoDownload opts → do
        authHeaders ← lift API.authHeaders
        H.liftEff $ Browser.newTab (DM.renderURL authHeaders opts)
        hideDialogNew
      DialogT.DoMountAction (DialogT.SaveMount path mount reply) → do
        API.saveMount path mount >>= case _ of
          Left err →
            case GE.fromQError err of
              Left msg →
                lift $ reply $ "There was a problem saving the mount: " <> msg
              Right ge →
                GE.raiseGlobalError ge
          Right _ →
            hideDialogNew
      DialogT.DoMountAction (DialogT.DeleteMount path) → do
        remove $ R.Mount (either R.Database R.View path)
        hideDialogNew
    pure next
  HandleNewDialog NewDialog.Dismiss next → do
    hideDialogNew
    pure next
  HandleHeader (Header.GlobalMenuMessage GlobalMenu.OpenAdminUI) next → do
    _ ← H.query' CS.cpAdminUI unit (H.action AdminUI.Types.Open)
    pure next
  HandleHeader _ next →
    pure next
  HandleNotifications NC.ExpandGlobalMenu next → do
    gripperState ← queryHeaderGripper $ H.request Gripper.GetState
    when (gripperState ≠ Just Gripper.Opened) do
      _ ← queryHeaderGripper $ H.action $ Gripper.StartDragging 0.0
      _ ← queryHeaderGripper $ H.action Gripper.StopDragging
      pure unit
    pure next
  HandleNotifications (NC.Fulfill trigger) next → do
    H.liftAff $ AVar.putVar trigger unit
    pure next
  HandleSearch m next → do
    salt ← H.liftEff newSalt
    st ← H.get
    value ← case m of
      Search.Cleared →
        pure Nothing
      Search.Submit → do
        H.query' CS.cpSearch unit $ H.request Search.GetValue
    H.liftEff $ Browser.setLocation $ browseURL value st.sort salt st.path
    pure next
  HandleLicenseProblem problem next → do
    _ ← H.query' CS.cpNotify unit $ H.action $ NC.UpdateRenderMode NC.Hidden
    _ ← H.query' CS.cpDialog unit $ H.action $ Dialog.Show $ Dialog.LicenseProblem problem
    pure next
  SetLoading bool next → do
    _ ← H.query' CS.cpSearch unit $ H.action $ Search.SetLoading bool
    pure next
  SetIsSearching bool next → do
    _ ← H.query' CS.cpListing unit $ H.action $ Listing.SetIsSearching bool
    pure next
  AddListings items next → do
    _ ← H.query' CS.cpListing unit $ H.action $ Listing.Adds items
    pure next
  ShowError message next → do
    showDialogNew (DialogT.Error message)
    pure next
  HandleSignInMessage message next → do
    when (message ≡ GlobalMenu.SignInSuccess) (H.liftEff Browser.reload)
    pure next
  HandleAdminUI message next → case message of
    AdminUI.Types.Closed → do
      _ ← queryHeaderGripper $ H.action $ Gripper.Close
      pure next

handleItemMessage ∷ Item.Message → DSL Unit
handleItemMessage = case _ of
  Item.Selected →
    pure unit
  Item.Edit res → do
    loc ← H.liftEff Browser.locationString
    for_ (preview R._Workspace res) \wp →
      H.liftEff $ Browser.setLocation $ append (loc ⊕ "/") $ mkWorkspaceURL wp (Load Editable)
  Item.Open res → do
    { sort, salt, path } ← H.get
    loc ← H.liftEff Browser.locationString
    for_ (preview R._filePath res) \fp →
      createWorkspace path \mkUrl →
        H.liftEff $ Browser.setLocation $ mkUrl $ Exploring fp
    for_ (preview R._dirPath res) \dp →
      H.liftEff $ Browser.setLocation $ browseURL Nothing sort salt dp
    for_ (preview R._Workspace res) \wp →
      H.liftEff $ Browser.setLocation $ append (loc ⊕ "/") $ mkWorkspaceURL wp (Load ReadOnly)
  Item.Configure (R.Mount mount) → do
    configure mount
  Item.Configure _ →
    pure unit
  Item.Move res → do
    showDialog $ Dialog.Rename res
    flip getDirectories rootDir \x →
      void $ H.query' CS.cpDialog unit $ H.action $ Dialog.AddDirsToRename x
  Item.Remove res →
    showDialogNew (DialogT.Delete res)
  Item.Share res → do
    path ← H.gets _.path
    loc ← map (_ ⊕ "/") $ H.liftEff Browser.locationString
    for_ (preview R._filePath res) \fp →
      createWorkspace path \mkUrl → do
        let url = append loc $ mkUrl $ Exploring fp
        showDialogNew (DialogT.Share (R.resourceName res) url)
    for_ (preview R._Workspace res) \wp → do
      let url = append loc $ mkWorkspaceURL wp (Load ReadOnly)
      showDialogNew (DialogT.Share (R.resourceName res) url)
  Item.Download res →
    showDialogNew (DialogT.Download res)

checkIsMount ∷ DirPath → DSL Unit
checkIsMount path = do
  isMount ← isRight <$> API.mountInfo (Left path)
  H.modify $ State._isMount .~ isMount

isMounted ∷ DSL Boolean
isMounted = do
  path ← H.gets _.path
  tailRecM go path
  where
  go ∷ DirPath → DSL (Step DirPath Boolean)
  go path = do
    isMount ← isRight <$> API.mountInfo (Left path)
    pure
      $ if isMount
          then Done true
          else maybe (Done false) Loop (parentDir path)

checkIsUnconfigured ∷ DSL Unit
checkIsUnconfigured = do
  isMount ← isRight <$> API.mountInfo (Left rootDir)
  isEmpty ← either (const false) Array.null <$> API.children rootDir
  H.modify $ State._isUnconfigured .~ (not isMount ∧ isEmpty)

remove ∷ Resource → DSL Unit
remove res = do
  -- Replace actual item with phantom
  _ ← H.query' CS.cpListing unit $ H.action $ Listing.Filter $ not ∘ eq res ∘ itemResource
  _ ← H.query' CS.cpListing unit $ H.action $ Listing.Add $ PhantomItem res
  -- Save order of items during deletion (or phantom will be on top of list)
  resort
  -- Try to delete
  mbTrashFolder ← H.lift $ API.delete res
  -- Remove phantom resource after we have response from server
  _ ← H.query' CS.cpListing unit $ H.action $ Listing.Filter $ not ∘ eq res ∘ itemResource
  case mbTrashFolder of
    Left err → do
      -- Error occured: put item back and show dialog
      void $ H.query' CS.cpListing unit $ H.action $ Listing.Add (Item res)
      case GE.fromQError err of
        Left m →
          showDialogNew $ DialogT.Error m
        Right ge →
          GE.raiseGlobalError ge
    Right mbRes →
      -- Item has been deleted: probably add trash folder
      for_ mbRes \res' →
        void $ H.query' CS.cpListing unit $ H.action $ Listing.Add (Item res')

  listing ← fromMaybe [] <$> (H.query' CS.cpListing unit $ H.request Listing.Get)
  path ← H.gets _.path
  presentMountHint listing path

  resort
  checkIsMount path
  checkIsUnconfigured

dismissMountHint ∷ DSL Unit
dismissMountHint = do
  LS.persist J.encodeJson LSK.dismissedMountHintKey true
  H.modify $ State._presentMountHint .~ false

dismissIntroVideo ∷ DSL Unit
dismissIntroVideo = do
  LS.persist J.encodeJson LSK.dismissedIntroVideoKey true
  H.modify $ State._presentIntroVideo .~ false
  void $ H.query' CS.cpNotify unit $ H.action $ NC.UpdateRenderMode NC.Notifications

dismissedIntroVideoBefore ∷ DSL Boolean
dismissedIntroVideoBefore =
  either (const false) id <$> LS.retrieve J.decodeJson LSK.dismissedIntroVideoKey

uploadFileSelected ∷ Cf.File → DSL Unit
uploadFileSelected f = do
  { path, sort, salt } ← H.get
  name ←
    H.liftEff (Cf.name f)
      <#> RX.replace (unsafePartial fromRight $ RX.regex "/" RXF.global) ":"
      >>= API.getNewName path

  case name of
    Left err → handleError err
    Right name' → do
      reader ← H.liftEff Cf.newReaderEff
      content' ← H.liftAff $ Cf.readAsBinaryString f reader

      let fileName = path </> file name'
          res = R.File fileName
          fileItem = PhantomItem res
          ext = Array.last (S.split (S.Pattern ".") name')
          mime = if ext ≡ Just "csv"
                 then textCSV
                 else if isApplicationJSON content'
                      then applicationJSON
                      else API.ldJSON
      _ ← H.query' CS.cpListing unit $ H.action (Listing.Add fileItem)
      f' ← API.makeFile fileName (CustomData mime content')
      _ ← H.query' CS.cpListing unit $ H.action $ Listing.Filter (not ∘ eq res ∘ itemResource)
      case f' of
        Left err → handleError err
        Right _ →
          void $ H.query' CS.cpListing unit $ H.action $ Listing.Add (Item res)

  where
  isApplicationJSON ∷ String → Boolean
  isApplicationJSON content'
    -- Parse if content is small enough
    | S.length content' < 1048576 = isRight $ J.jsonParser content'
    -- Or check if its first/last characters are [/]
    | otherwise =
        let trimmed = S.trim content'
        in (startsWithEndsWith "[" "]" trimmed) || (startsWithEndsWith "{" "}" trimmed)

  startsWithEndsWith startsWith endsWith s =
    F.all isJust [S.stripPrefix (S.Pattern startsWith) s, S.stripSuffix (S.Pattern endsWith) s]

  handleError err =
    case GE.fromQError err of
      Left msg → showDialogNew $ DialogT.Error msg
      Right ge → GE.raiseGlobalError ge

presentMountHint ∷ ∀ a. Array a → DirPath → DSL Unit
presentMountHint xs path = do
  isSearching ←
    map (fromMaybe false) $ H.query' CS.cpSearch unit (H.request Search.IsSearching)
  isLoading ←
    map (fromMaybe true)  $ H.query' CS.cpSearch unit (H.request Search.IsLoading)

  H.modify
    ∘ (State._presentMountHint .~ _)
    ∘ ((Array.null xs ∧ path ≡ rootDir ∧ not (isSearching ∧ isLoading)) ∧ _)
    ∘ not
    ∘ either (const false) id
    =<< dismissedBefore
  where
  dismissedBefore ∷ DSL (Either String Boolean)
  dismissedBefore =
    LS.retrieve J.decodeJson LSK.dismissedMountHintKey

dismissSignInSubmenu ∷ DSL Unit
dismissSignInSubmenu =
  void $ queryGlobalMenu (H.action GlobalMenu.DismissSubmenu)

resort ∷ DSL Unit
resort = do
  sort ← H.gets _.sort
  H.query' CS.cpSearch unit (H.request Search.IsSearching)
    >>= traverse_ \isSearching →
      void $ H.query' CS.cpListing unit $ H.action $ Listing.SortBy (sortItem isSearching sort)

configure ∷ R.Mount → DSL Unit
configure m = do
  let anyPath = R.mountPath m
  API.mountInfo anyPath >>= case m, _ of
    R.View path, Left err → raiseError err
    R.Database path, Left err
      | path /= rootDir → raiseError err
      | otherwise → showMountDialog Mount.Root
    R.View path, Right mount →
      showMountDialog $ Mount.Edit
        { parent: either parentDir parentDir anyPath
        , name: Just $ getNameStr anyPath
        , mount
        }
    R.Database path, Right mount →
      showMountDialog $ Mount.Edit
        { parent: if path ≡ rootDir then Nothing else either parentDir parentDir anyPath
        , name: if path ≡ rootDir then Nothing else Just $ getNameStr anyPath
        , mount
        }
  where
    raiseError ∷ QE.QError → DSL Unit
    raiseError err = case GE.fromQError err of
      Left msg →
        showDialogNew $ DialogT.Error
          $ "There was a problem reading the mount settings: " <> msg
      Right ge →
        GE.raiseGlobalError ge
    showMountDialog ∷ Mount.Input → DSL Unit
    showMountDialog = showDialogNew ∘ DialogT.Mount

getChildren
  ∷ (R.Resource → Boolean)
  → (Array R.Resource → DSL Unit)
  → DirPath
  → DSL Unit
getChildren pred cont start = do
  ei ← API.children start
  case ei of
    Right items → do
      let items' = Array.filter pred items
          parents = Array.mapMaybe (either Just (const Nothing) ∘ R.getPath) items
      cont items'
      traverse_ (getChildren pred cont) parents
    _ → pure unit

getDirectories ∷ (Array R.Resource → DSL Unit) → DirPath → DSL Unit
getDirectories = getChildren $ R.isDirectory ∨ R.isDatabaseMount

showDialog ∷ Dialog.Dialog → DSL Unit
showDialog = void ∘ H.query' CS.cpDialog unit ∘ H.action ∘ Dialog.Show

hideDialog ∷ DSL Unit
hideDialog = void $ H.query' CS.cpDialog unit $ H.action Dialog.RaiseDismiss

showDialogNew ∷ DialogT.Definition → DSL Unit
showDialogNew d = H.modify (_ { dialog = Just d })

hideDialogNew ∷ DSL Unit
hideDialogNew = H.modify (_ { dialog = Nothing })

queryHeaderGripper ∷ ∀ a. Gripper.Query a → DSL (Maybe a)
queryHeaderGripper =
   H.query' CS.cpHeader unit ∘ Header.QueryGripper ∘ liftCoyoneda

queryGlobalMenu ∷ ∀ a. GlobalMenu.Query a → DSL (Maybe a)
queryGlobalMenu =
   H.query' CS.cpHeader unit ∘ Header.QueryGlobalMenu ∘ liftCoyoneda

createWorkspace ∷ ∀ a. DirPath → ((Action → String) → DSL a) → DSL Unit
createWorkspace path action = do
  let newWorkspaceName = Config.newWorkspaceName ⊕ "." ⊕ Config.workspaceExtension
  name ← API.getNewName path newWorkspaceName
  case name of
    Left err →
      case GE.fromQError err of
        Left msg →
          -- This error isn't strictly true as we're not actually creating the
          -- workspace here, but saying there was a problem "creating a name for the
          -- workspace" would be a little strange
          showDialogNew $ DialogT.Error
            $ "There was a problem creating the workspace: " ⊕ msg
        Right ge →
          GE.raiseGlobalError ge
    Right name' →
      void $ action (mkWorkspaceURL (path </> dir name'))
