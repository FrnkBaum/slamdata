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

module SlamData.Quasar.Query
  ( compile
  , compile'
  , queryEJson
  , queryEJsonVM
  , query
  , viewQuery
  , viewQuery'
  , all
  , sample
  , count
  , fileQuery
  , fields
  , jcursorToSql
  , module Quasar.Error
  , module SlamData.Quasar.Class
  ) where

import SlamData.Prelude

import Data.Argonaut as JS
import Data.Array as Arr
import Data.Int as Int
import Data.Lens ((.~))
import Data.List as L
import Data.Json.Extended as EJS
import Data.Path.Pathy as P
import Data.Set as Set
import Data.StrMap as SM

import Matryoshka (Coalgebra, ana, project, embed)

import Quasar.Advanced.QuasarAF as QF
import Quasar.Data (JSONMode(..))
import Quasar.Error (QError)
import Quasar.Mount as QM
import Quasar.Types (DirPath, FilePath, CompileResultR)

import SlamData.Quasar.Class (class QuasarDSL, liftQuasar)

import SqlSquare (Sql, print)
import SqlSquare as Sql

import Utils.SqlSquare (tableRelation)

-- | Compiles a query.
compile
  ∷ ∀ m
  . QuasarDSL m
  ⇒ DirPath
  → Sql
  → SM.StrMap String
  → m (Either QError CompileResultR)
compile backendPath sql varMap =
  compile' backendPath (print sql) varMap

compile'
  ∷ ∀ m
  . QuasarDSL m
  ⇒ DirPath
  → String
  → SM.StrMap String
  → m (Either QError CompileResultR)
compile' backendPath sql varMap =
  liftQuasar $ QF.compileQuery backendPath sql varMap

query
  ∷ ∀ m
  . QuasarDSL m
  ⇒ DirPath
  → Sql
  → m (Either QError JS.JArray)
query path sql =
  liftQuasar $ QF.readQuery Readable path (print sql) SM.empty Nothing

queryEJson
  ∷ ∀ m
  . QuasarDSL m
  ⇒ DirPath
  → Sql
  → m (Either QError (Array EJS.EJson))
queryEJson path sql =
  liftQuasar $ QF.readQueryEJson path (print sql) SM.empty Nothing

queryEJsonVM
  ∷ ∀ m
  . QuasarDSL m
  ⇒ DirPath
  → Sql
  → SM.StrMap String
  → m (Either QError (Array EJS.EJson))
queryEJsonVM path sql vm =
  liftQuasar $ QF.readQueryEJson path (print sql) vm Nothing

-- | Runs a query creating a view mount for the query.
viewQuery
  ∷ ∀ m
  . (QuasarDSL m, Monad m)
  ⇒ FilePath
  → Sql
  → SM.StrMap String
  → m (Either QError Unit)
viewQuery dest sql vars = viewQuery' dest (print sql) vars

-- | Runs a query creating a view mount for the query.
viewQuery'
  ∷ ∀ m
  . (QuasarDSL m, Monad m)
  ⇒ FilePath
  → String
  → SM.StrMap String
  → m (Either QError Unit)
viewQuery' dest sql vars = do
  liftQuasar $
    QF.deleteMount (Right dest)
  liftQuasar $
    QF.updateMount (Right dest) (QM.ViewConfig
      { query: sql
      , vars
      })

fileQuery
  ∷ ∀ m
  . QuasarDSL m
  ⇒ DirPath
  → FilePath
  → Sql
  → SM.StrMap String
  → m (Either QError FilePath)
fileQuery backendPath dest sql vars =
  liftQuasar $ map _.out <$>
    QF.writeQuery backendPath dest (print sql) vars


all
  ∷ ∀ m
  . QuasarDSL m
  ⇒ FilePath
  → m (Either QError JS.JArray)
all file =
  liftQuasar $ QF.readFile Readable file Nothing

sample
  ∷ ∀ m
  . QuasarDSL m
  ⇒ FilePath
  → Int
  → Int
  → m (Either QError JS.JArray)
sample file offset limit =
  liftQuasar $ QF.readFile Readable file (Just { limit, offset })

count
  ∷ ∀ m
  . (Monad m, QuasarDSL m)
  ⇒ FilePath
  → m (Either QError Int)
count file = runExceptT do
  let
    backendPath = fromMaybe P.rootDir (P.parentDir file)
    sql =
      Sql.buildSelect
      $ (Sql._projections
         .~ (L.singleton
               $ Sql.projection
                   (Sql.invokeFunction "COUNT" $ L.singleton $ Sql.splice Nothing)
                   #  Sql.as "total"))
      ∘ (Sql._relations .~ tableRelation file)
  result ← ExceptT $ liftQuasar $
    QF.readQuery Readable backendPath (print sql) SM.empty Nothing
  pure $ fromMaybe 0 (readTotal result)
  where
  readTotal ∷ JS.JArray → Maybe Int
  readTotal =
    Int.fromNumber
      <=< JS.toNumber
      <=< SM.lookup "total"
      <=< JS.toObject
      <=< Arr.head

data UnfoldableJC = JC JS.JCursor | S String | I Int

jcCoalgebra ∷ Coalgebra (Sql.SqlF EJS.EJsonF) UnfoldableJC
jcCoalgebra = case _ of
  S s → Sql.Ident s
  I i → Sql.Literal (EJS.Integer i)
  JC cursor → case cursor of
    JS.JCursorTop → Sql.Splice Nothing
    JS.JIndex i c → Sql.Binop { op: Sql.IndexDeref, lhs: JC c, rhs: I i }
    JS.JField f c → Sql.Binop { op: Sql.FieldDeref, lhs: JC c, rhs: S f }

removeTopSplice ∷ Sql → Sql
removeTopSplice = project ⋙ case _ of
  op@(Sql.Binop { lhs, rhs }) → case project lhs of
    Sql.Splice Nothing → rhs
    _ → embed op
  a → embed a

jcursorToSql ∷ JS.JCursor → Sql
jcursorToSql = removeTopSplice ∘ ana jcCoalgebra ∘ JC ∘ JS.insideOut

allFields ∷ JS.JArray → L.List Sql
allFields =
  map jcursorToSql
  ∘ L.fromFoldable
  ∘ foldMap (Set.fromFoldable ∘ map fst)
  ∘ map JS.toPrims

fields
  ∷ ∀ m
  . (Monad m, QuasarDSL m)
  ⇒ FilePath
  → m (QError ⊹ (L.List Sql))
fields file = runExceptT do
  jarr ← ExceptT $ sample file 0 100
  pure $ allFields jarr
