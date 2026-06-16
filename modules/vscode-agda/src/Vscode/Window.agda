module Vscode.Window where

open import Agda.Builtin.Unit
open import Agda.Builtin.Nat
open import Data.String
open import Data.Maybe
open import Data.Bool
open import Data.List
open import Function

open import Data.IO
open import Data.JSON hiding (encode)

open import Vscode.Common
open import Vscode.SemanticTokensProvider
open import Vscode.TextEditor

postulate on-did-change-active-text-editor-listener : (Maybe TextEditor.t → IO ⊤) → IO Disposable.t
{-# COMPILE JS on-did-change-active-text-editor-listener = update => async () =>
    AgdaModeImports.vscode.window.onDidChangeActiveTextEditor(editor =>
      update(editor ? (a => a["just"](editor)) : (a => a["nothing"]()))(() => {})) #-}

module StatusBarItem where
  postulate t : Set

  data Alignment : Set where
    left right : Alignment

  encode-alignment : Alignment → Nat
  encode-alignment left = 1
  encode-alignment right = 2

  private module Internal where
    postulate create : String → Nat → Maybe Nat → IO t
    {-# COMPILE JS create = id => align => prio => async () => {
      const prio_ = prio({ "just": a => a, "nothing": () => undefined });
      return AgdaModeImports.vscode.window.createStatusBarItem(id, Number(align), prio_);
    } #-}

  -- TODO: StatusBarItems are disposable
  create : String → Alignment → Maybe Nat → IO t
  create id align priority = Internal.create id (encode-alignment align) priority

  postulate set-text : t → String → IO ⊤
  {-# COMPILE JS set-text = item => text => async () => { item.text = text; return a => a["tt"]() } #-}

  postulate show : t → IO ⊤
  {-# COMPILE JS show = item => async () => { item.show(); return a => a["tt"]() } #-}

  postulate hide : t → IO ⊤
  {-# COMPILE JS hide = item => async () => { item.hide(); return a => a["tt"]() } #-}

module TextDocumentShowOptions where
  open import Data.Bool
  open import Vscode.Panel

  record t : Set where field
    preserve-focus preview : Bool
    selection : Range.t
    view-column : ViewColumn.t
  open t public

module QuickPickItem where
  data Kind : Set where
    separator default : Kind
  {-# COMPILE JS Kind = ((x, v) => x === -1 ? v["separator"]() : v["default"]()) #-}
  {-# COMPILE JS separator = -1 #-}
  {-# COMPILE JS default = 0 #-}

  record t : Set where
    constructor make-QuickPickItem
    field
      always-show? picked? : Bool
      description detail : Maybe String
      kind : Kind
      label : String
  open t public

  {-# COMPILE JS t = ((x, v) => v["make-QuickPickItem"](
    x.alwaysShow ?? false,
    x.picked ?? false,
    x.description === undefined ? (a => a["nothing"]()) : (a => a["just"](x.description)),
    x.detail === undefined ? (a => a["nothing"]()) : (a => a["just"](x.detail)),
    x.kind,
    x.label
  )) #-}
  {-# COMPILE JS make-QuickPickItem = alwaysShow => picked => description => detail => kind => label => {
    return {
      kind, label, alwaysShow, picked,
      description: description({ "just": x => x, "nothing": () => undefined }),
      detail: detail({ "just": x => x, "nothing": () => undefined })
    };
  } #-}
  {-# COMPILE JS t.always-show? = ({ alwaysShow }) => alwaysShow ?? false #-}
  {-# COMPILE JS t.picked? = ({ picked }) => picked ?? false #-}
  {-# COMPILE JS t.description = ({ description }) => description === undefined
    ? (a => a["nothing"]()) : (a => a["just"](description)) #-}
  {-# COMPILE JS t.detail = ({ detail }) => detail === undefined
    ? (a => a["nothing"]()) : (a => a["just"](detail)) #-}
  {-# COMPILE JS t.kind = ({ kind }) => kind ?? 0 #-}
  {-# COMPILE JS t.label = ({ label }) => label #-}

  empty : Kind → String → t
  empty k l = record
    { kind = k ; label = l ; always-show? = false
    ; picked? = false ; description = nothing ; detail = nothing
    }

open QuickPickItem using (always-show? ; picked? ; description ; detail ; kind ; label ; Kind)

module Window where
  open import Vscode.Panel
  open TextDocumentShowOptions

  module Internal where
    open import Data.Int

    postulate show-text-document : Uri.t → TextDocumentShowOptions.t → Int → IO TextEditor.t
    {-# COMPILE JS show-text-document = uri => options => viewColumn => () => new Promise((resolve, reject) =>
      options["record"]({
        record: (a, b, c, _) =>
          AgdaModeImports.vscode.window.showTextDocument(uri, {
            preserveFocus: a, preview: b, selection: c, viewColumn: viewColumn
          }).then(resolve).catch(reject)
      })
    ) #-}

  show-text-document : Uri.t → TextDocumentShowOptions.t → IO TextEditor.t
  show-text-document uri options =
    Internal.show-text-document uri options (ViewColumn.encode (options .view-column))

  postulate show-input-box : IO (Maybe String)
  {-# COMPILE JS show-input-box = async () => {
    const answer = await AgdaModeImports.vscode.window.showInputBox();
    return answer ? (a => a["just"](answer)) : (a => a["nothing"]());
  } #-}

  postulate quick-pick : List String → IO String
  {-# COMPILE JS quick-pick = options => async () => {
    return await AgdaModeImports.vscode.window.showQuickPick(options);
  } #-}

  postulate quick-pick-with-items : List QuickPickItem.t → IO (Maybe QuickPickItem.t)
  {-# COMPILE JS quick-pick-with-items = options => async () => {
    const result = await AgdaModeImports.vscode.window.showQuickPick(options);
    return result ? (a => a["just"](result)) : (a => a["nothing"]());
  } #-}

  postulate show-information-message show-error-message : String → List String → IO (Maybe String)
  {-# COMPILE JS show-information-message = msg => items => async () => {
    const answer = await AgdaModeImports.vscode.window.showInformationMessage(msg, ...items.map(i => ({ title: i })));
    return answer ? (a => a["just"](answer.title)) : (a => a["nothing"]());
  } #-}
  {-# COMPILE JS show-error-message = msg => items => async () => {
    const answer = await AgdaModeImports.vscode.window.showErrorMessage(msg, ...items.map(i => ({ title: i })));
    return answer ? (a => a["just"](answer.title)) : (a => a["nothing"]());
  } #-}

  postulate visible-editors : IO (List TextEditor.t)
  {-# COMPILE JS visible-editors = async () => AgdaModeImports.vscode.window.visibleTextEditors #-}