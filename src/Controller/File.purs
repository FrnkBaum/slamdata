-- | File component main handler 
module Controller.File (
  handler,
  getDirectories,
  selectThis,
  rename,
  checkRename,
  renameItemClicked
  ) where

import Control.Monad.Eff
import Control.Monad.Eff.Class
import Control.Monad.Eff.Exception
import Control.Monad.Error.Class
import Control.Monad.Eff.Random
import Control.Monad.Aff.Class
import Control.Monad.Trans
import Control.Plus (empty)


import DOM
import Data.Maybe
import Data.Tuple
import Data.Either
import Data.Foldable
import Data.Traversable
import Control.Apply


import Data.DOM.Simple.Types
import Data.DOM.Simple.Document
import Data.DOM.Simple.Window
import Data.DOM.Simple.Element
import EffectTypes

import qualified Utils as U
import qualified Utils.Event as Ue
import qualified Utils.File as Uf
import qualified Data.Array as A
import qualified Halogen as Hl
import qualified Control.Timer as Tm
import qualified Config as Config
import qualified Control.Monad.Aff as Aff
import qualified Text.SlamSearch as S
import qualified Routing.Hash as Rh
import qualified Data.String as Str
import qualified Driver.File as Cd 
import qualified Network.HTTP.Affjax as Af

import qualified Data.String.Regex as Rgx
import qualified Model.File as M
import qualified Model.Item as Mi
import qualified Model.Notebook as Mn
import qualified Model.Resource as Mr
import qualified Api.Fs as Api
import qualified Control.UI.ZClipboard as Z

import qualified Halogen.HTML.Events.Handler as E
import qualified Halogen.HTML.Events.Monad as E
import qualified Halogen.HTML.Events.Types as Et

handler :: forall e. M.Request -> E.Event (FileAppEff e) M.Input
handler r = 
  case r of
    M.Delete item -> E.async $ do 
      Api.deleteItem item
      pure $ M.Remove item

    M.CreateNotebook state -> do
      let name = getNewName Config.newNotebookName state
      path <- liftEff $ Cd.getPath <$> Rh.getHash
      let notebook = Mi.initNotebook{root = path, name = name, phantom = true}
      -- immidiately updating state and then
      (pure $ M.ItemAdd notebook) `E.andThen` \_ -> do
        f <- liftAff $ Aff.attempt $ Api.makeNotebook notebook Mn.newNotebook
        (pure $ M.Remove notebook) `E.andThen` \_ ->  do
          case f of
            Left _ -> empty
            Right _ -> do
              liftEff $ open notebook{phantom = false} false
              -- and add real notebook to list
              pure $ M.ItemAdd notebook{phantom = false}

        
    M.FileListChanged node state -> do
      fileArr <- Uf.fileListToArray <$> (liftAff $ Uf.files node)
      liftEff $ U.clearValue node
      case A.head fileArr of
        Nothing ->
          let err :: Aff.Aff (FileAppEff e) M.Input
              err = throwError $ error "empty filelist"
          in liftAff err
        Just file -> do
          let newReader :: Eff (FileAppEff e) _
              newReader = Uf.newReaderEff

              readAsBinaryString :: _ -> _ -> Aff.Aff (FileAppEff e) _
              readAsBinaryString = Uf.readAsBinaryString
              
          path <- liftEff (Cd.getPath <$> Rh.getHash) 
          name <- flip getNewName state <$> (liftEff $ Uf.name file)
          let fileItem = Mi.initFile{root = path, name = name, phantom = true}
              
          reader <- liftEff newReader 
          content <- liftAff $ readAsBinaryString file reader
          
          (pure $ M.ItemAdd fileItem) `E.andThen` \_ -> do
            f <- liftAff $ Aff.attempt $ Api.makeFile fileItem content
            (pure $ M.Remove fileItem) `E.andThen` \_ -> do
              case f of
                Left _ -> empty
                Right _ -> do
                  liftEff $ open fileItem{phantom = false} false
                  pure $ M.ItemAdd fileItem{phantom = false}

                  
    M.Move item -> do
      (pure $ M.SetDialog (Just (M.RenameDialog $ M.initialRenameDialog item)))
        `E.andThen` \_ -> do
        getDirectories "/" 

    M.SetSort sort -> do
      liftEff $ Rh.modifyHash $ Cd.updateSort sort
      empty

            -- opens item
    M.Open item -> do
      liftEff $ case item.resource of
        Mr.Directory ->
          moveDown item
        Mr.Database ->
          moveDown item
        Mr.File ->
          open item true
        Mr.Table ->
          open item true
        Mr.Notebook -> 
          open item false
      empty

            -- clicked on breadcrumb
    M.Breadcrumb b -> do
      liftEff $ Rh.modifyHash $ Cd.updatePath b.link
      empty

    -- clicked on _Folder_ link, create phantom folder
    M.CreateFolder state -> do
      let name = getNewName Config.newFolderName state
      path <- liftEff (Cd.getPath <$> Rh.getHash)
      pure $ M.ItemAdd $ Mi.initDirectory{root = path, name = name}



    -- clicked on _File_ link triggering file uploading
    M.UploadFile node _ -> do
      let el = U.convertToElement node
      mbInput <- liftEff $ querySelector "input" el
      case mbInput of 
        Nothing -> empty 
        Just input -> do
          liftEff $ Ue.raiseEvent "click" input
          empty

    M.MountDatabase _ ->
      pure $ M.SetDialog (Just M.MountDialog)

    M.Configure _ -> do
      pure $ M.SetDialog (Just M.ConfigureDialog)


    M.SearchSubmit s p -> do
      liftEff $ maybe (pure unit) Tm.clearTimeout s.timeout
      setQE (s.nextValue <> " +path:" <> p)


    M.SearchClear isSearching search -> do
      liftEff $ maybe (pure unit) Tm.clearTimeout search.timeout
      if isSearching then do
        rnd <- show <$> (liftEff $ randomInt 1000000 2000000)
        liftEff (Rh.modifyHash $ Cd.updateSalt rnd)
        pure $ M.Loading false
        else 
        setQE "path:/"
        
    M.SearchChange search ch p -> E.async $ Aff.makeAff $ \_ k -> do
      k $ M.SearchNextValue ch
      maybe (pure unit) Tm.clearTimeout search.timeout
      tim <- Tm.timeout Config.searchTimeout $ do
        E.runEvent (const $ pure unit) (const $ pure unit) $
          setQE (ch <> " path:\"" <> p <> "\"")
      k $ M.SearchTimeout tim
      k $ M.SearchValidation true
      
-- ATTENTION 
-- This works too slow 
--      (pure $ M.SearchNextValue ch) `E.andThen` \_ -> do
--        tim <- liftEff $ Tm.timeout Config.searchTimeout $ do
--          E.runEvent (const $ pure unit) (const $ pure unit) $
--            setQE (ch <> " path:\"" <> p <> "\"")
--        (pure $ M.SearchTimeout tim) `E.andThen` \_ -> do
--          pure $ M.SearchValidation true

      
    -- ATTENTION 
    -- This all should be moved to `initializer`
    -- ATTENTION
    M.Share item -> E.async $ Aff.makeAff $ \_ k -> do
      url <- itemURL item
      k $ M.SetDialog (Just $ M.ShareDialog url)
      mbCopy <- document globalWindow >>= getElementById "copy-button"
      case mbCopy of
        Nothing -> pure unit
        Just btn -> void do
          Z.make btn >>= Z.onCopy (Z.setData "text/plain" url)

  where itemURL item = do
          loc <- U.locationString
          hash <- Rh.getHash
          let newUrl = loc <> case item.resource of
                Mr.File -> foldl (<>) ""
                     [Config.notebookUrl,
                      "#", Mi.itemPath item,
                      "/view",
                      "/?q=", U.encodeURIComponent ("select * from ...")
                     ]
                Mr.Notebook -> foldl (<>) ""
                     [Config.notebookUrl,
                      "#", Mi.itemPath item,
                      "/view"]
                _ -> "#" <> Cd.updatePath (item.root <> "/" <> item.name) hash
          pure $ newUrl 


        setQE q = do
          case S.mkQuery q of
            Left _ | q /= "" -> pure $ M.SearchValidation false
            Right _ -> do
              liftEff (Rh.modifyHash $ Cd.updateQ q)
              pure $ M.SearchValidation true
            _ -> do
              liftEff (Rh.modifyHash $ Cd.updateQ "")
              pure $ M.SearchValidation true

        -- open dir or db
        moveDown item = Rh.modifyHash $ Cd.updatePath (item.root <> "/" <> item.name <> "/")
        -- open notebook or file
        open item isNew = U.newTab $ foldl (<>) ""
                          ([Config.notebookUrl,
                            "#", Mi.itemPath item,
                            "/edit"] <>
                             if isNew then 
                             ["/?q=", U.encodeURIComponent ("select * from ...")]
                           else [])
        -- get fresh name for this state
        getNewName :: String -> M.State -> String
        getNewName name state =
          if A.findIndex (\x -> x.name == name) state.items /= -1 then
            getNewName' name 1
            else name
          where getNewName' name i =
                  -- Str.split and Str.joinWith work with []
                  -- converting from/to List will be too expensive 
                  case Str.split "." name of
                    [] -> "" 
                    body:suffixes ->
                      let newName = Str.joinWith "." $ (body <> show i):suffixes 
                      in if A.findIndex
                            (\x -> x.name == newName)
                            state.items /= -1 
                         then getNewName' name (i + 1)
                         else newName 

getDirectories :: forall e. String -> E.Event (FileAppEff e) M.Input
getDirectories path = do
  ei <- liftAff $ Aff.attempt $ Api.listing path
  case ei of
    Right items -> do
      let children = A.filter (\x -> x.resource == Mr.Directory ||
                                   x.resource == Mr.Database) items
          directories = (\x -> path <> x.name <> "/") <$> children

      (pure $  M.AddRenameDirs directories) `E.andThen` \_ ->
        fold (getDirectories <$> directories)
    _ -> empty


selectThis :: forall e o. Et.Event (|o) ->
              E.EventHandler (E.Event (dom :: DOM|e) M.Input)
selectThis ev = 
  pure $ (E.async $ Aff.makeAff \_ _ -> U.select ev.target)

import Debug.Foreign

rename :: forall e. Mi.Item -> String ->
          E.EventHandler (E.Event (FileAppEff e) M.Input)
rename item dest = pure do
  let o = fprintUnsafe dest 
      move :: Aff.Aff (FileAppEff e) String
      move = Api.moveItem item dest
  errorString <- liftAff $ move
  (pure $ M.RenameError errorString) `E.andThen` \_ -> do
    case errorString of
      "" -> do liftEff U.reload
               empty
      _ -> empty

checkRename :: forall e. String -> M.RenameDialogRec ->
               E.EventHandler (E.Event (FileAppEff e) M.Input)
checkRename name r = pure do
  if name == ""
    then pure $ M.RenameError "Please, enter new name"
    else
    (if Str.indexOf "/" name /= -1
     then pure $ M.RenameError "Incorrect File Name"
     else checkList name r.selectedContent) `E.andThen` \_ -> 
    pure $ M.RenameChanged name

renameItemClicked :: forall e. String -> String -> 
                     E.EventHandler (E.Event (FileAppEff e) M.Input)
renameItemClicked target dir = pure $ do
  (pure $ M.SetRenameSelected dir) `E.andThen` \_ -> do
    items <- liftAff $ Api.listing dir
    let list = _.name <$> items
    (pure $ M.RenameSelectedContent list) `E.andThen` \_ ->
      checkList target list 

checkList :: forall e. String -> [String] -> E.Event (FileAppEff e) M.Input 
checkList target list =
  pure case A.elemIndex target list of 
    -1 -> M.RenameError ""
    _ ->  M.RenameError "Item with such name exists in target folder"