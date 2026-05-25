module AgdaMode.Extension where

-- TODO: Combine these into some sort of importable prelude with explicit qualifiers
open import Agda.Builtin.Unit
open import Data.Maybe
import Data.Maybe.Effectful
open import Data.String hiding (_==_)
import Data.String as String
open import Data.Product
open import Data.Bool
open import Data.List
import Data.List as List
open import Function hiding (id)
open import Data.Nat
open import Data.Int hiding (pos ; _+_)
import Data.Int as Int
open import Class.Show
open import Class.Monoid
open import Class.Ord

import Data.IO as IO
open IO using (IO)
open import Data.JSON
open import Data.JSON.Decode
open import Data.Map
open import Node.FileSystem

open import AgdaMode.Extension.Highlighting
open import AgdaMode.Extension.Highlighting.Decode
open import AgdaMode.Extension.Highlighting.Legend
open import AgdaMode.Extension.Keymap
open import AgdaMode.Extension.Response
open import AgdaMode.Extension.Model
open import AgdaMode.Extension.Position
open import AgdaMode.Extension.ProcessQueue

open import Vscode.Common as VSC
open import Vscode.Command as VSC
open import Vscode.Panel as VSC
open import Vscode.SemanticTokensProvider as VSC
open import Vscode.Window as VSC
open import Vscode.TextEditor as VSC
open import Vscode.Logging

postulate trace : {A : Set} → A → IO ⊤
{-# COMPILE JS trace = A => a => async () => { console.log(a); return b => b["tt"]() } #-}

postulate unsafe-trace : {A B : Set} → A → B → B
{-# COMPILE JS unsafe-trace = A => B => a => b => { console.log(a); return b } #-}

postulate try : ∀ {ℓ} {A : Set ℓ} → (⊤ → A) → A
{-# COMPILE JS try = _ => _ => thing => {
  try { return thing(a => a["tt"]()) } catch (e) { console.error(e); throw e; }
} #-}

postulate throw : ∀ {ℓ} {A : Set ℓ} {E : Set} → E → IO A
{-# COMPILE JS throw = _ => _ => _ => e => async () => { throw e } #-}

-- Actual app

open IO.Effectful

open import Effect.Monad
open Monad {{ ... }}
open MonadPlus {{ ... }} using (⊘ ; _<|>_)
open TraversableM {{ ... }} 

init : Trie.t → IO Model
init keymap = do
  tokens-request-emitter ← EventEmitter.new
  sbi₁ ← StatusBarItem.create "agdaMode.statusBar" StatusBarItem.right nothing
  sbi₂ ← StatusBarItem.create "agdaMode.inputMode" StatusBarItem.left nothing
  let open DecorationType
  dec₁ ← Options.new >>= create ∘ Options.set-text-decoration "underline"
  dec₂ ← Options.new >>= create ∘ Options.set-theme-background-colour "editor.selectionHighlightBackground"
  pure record
    { panel = nothing
    ; status-bar-item = sbi₁
    ; input-mode-status-item = sbi₂
    ; stdout-buffer = ""
    ; current-doc = nothing
    ; loaded-files = StringMap.empty
    ; agda = nothing
    ; tokens-request-emitter = tokens-request-emitter
    ; running-info = ""
    ; underline-decoration = dec₁
    ; ip-decoration = dec₂
    ; keymap = keymap
    }

goal-context-cmds : StringMap.t (Rewrite.t → InteractionPoint.t → AgdaCommand.t)
goal-context-cmds = StringMap.empty
  |> StringMap.insert "agda-mode.goal-context" AgdaCommand.context
  |> StringMap.insert "agda-mode.goal-type" AgdaCommand.goal-type
  |> StringMap.insert "agda-mode.goal-env" AgdaCommand.goal-type-context
  |> StringMap.insert "agda-mode.goal-context-infer" AgdaCommand.goal-type-context-infer
  |> StringMap.insert "agda-mode.goal-context-elab" AgdaCommand.goal-type-context-check
  |> StringMap.insert "agda-mode.auto-goal" AgdaCommand.auto-goal

goal-give-cmds : StringMap.t (Bool → InteractionPoint.t → AgdaCommand.t)
goal-give-cmds = StringMap.empty
  |> StringMap.insert "agda-mode.refine" AgdaCommand.refine-or-intro
  |> StringMap.insert "agda-mode.give-goal" AgdaCommand.give

show-general-info-cmds : StringMap.t (Rewrite.t → AgdaCommand.t)
show-general-info-cmds = StringMap.empty
  |> StringMap.insert "agda-mode.show-constraints" AgdaCommand.show-constraints
  |> StringMap.insert "agda-mode.show-metas" AgdaCommand.show-metas

backends : StringMap.t Backend.t
backends = (ghc true ∷ ghc false ∷ js ∷ html ∷ latex ∷ quicklatex ∷ [])
  |> foldr StringMap.empty λ m b → StringMap.insert (show b) b m

toggle-cmds : StringMap.t AgdaCommand.t
toggle-cmds = StringMap.empty
  |> StringMap.insert "agda-mode.toggle-hidden" AgdaCommand.toggle-hidden
  |> StringMap.insert "agda-mode.toggle-irrelevant" AgdaCommand.toggle-irrelevant

-- TODO: Turn this into decoders?
postulate GiveArgsObject : Set
postulate get-pmLambda : GiveArgsObject → Bool
{-# COMPILE JS get-pmLambda = o => o?.pmLambda ?? false #-}
postulate get-compute-mode-string : GiveArgsObject → String
{-# COMPILE JS get-compute-mode-string = o => o?.computeMode ?? "" #-}
postulate get-rewrite-string : GiveArgsObject → String
{-# COMPILE JS get-rewrite-string = o => o?.rewrite ?? "" #-}


update-input-mode : Trie.t → DecorationType.t → StatusBarItem.t → IO.Ref.t InputMode.Model → InputMode.Msg → IO ⊤
update-input-mode t d stb input-mode-model msg = TextEditor.active-editor >>= λ where
  (just e) → IO.Ref.get input-mode-model >>= λ where
    (just m) → do
      model ← InputMode.update (t , e) (just m) msg
      model ← InputMode.view e d stb model
      IO.Ref.set input-mode-model model
    nothing → case msg of λ where
      (InputMode.character c) → do
        model ← InputMode.update (t , e) nothing c
        model ← InputMode.view e d stb model
        IO.Ref.set input-mode-model model
      _ → pure tt
  nothing → pure tt

with-loaded-file : String → (File → IO File) → Model → IO Model
with-loaded-file path f model = model .loaded-files !? path |> maybe (pure model) λ file → do
  new-file ← f file
  pure $ record model { loaded-files = model .loaded-files [ path ]:= new-file }

with-current-file : (TextEditor.t → TextDocument.t → File → IO File) → Model → IO Model
with-current-file f model = TextEditor.active-editor >>= maybe (pure model) λ e →
  TextEditor.document e >>= λ doc → model |> with-loaded-file (TextDocument.file-name doc) (f e doc)

jump-to-position : TextDocument.t → Position.t → IO ⊤
jump-to-position doc pos =
  let uri = TextDocument.uri doc in
  tt <$ Window.show-text-document uri record
    { preserve-focus = true
    ; preview = false
    ; selection = Range.new pos pos
    ; view-column = ViewColumn.active
    }

jump-to-goal : Model → (Position.t → List InteractionPoint.t → Maybe InteractionPoint.t) → IO Model
jump-to-goal model find-next = model |> with-current-file λ ed doc file → do
  pos ←(TextEditor.cursor-pos ed)
  find-next pos (file .interaction-points) |> maybe (pure file) λ ip →
    file <$ jump-to-position doc (Position.right 3 (Range.start (ip .range)))

compare-doc : TextDocument.t → TextDocument.t → Bool
compare-doc = String._==_ on (Uri.to-string ∘ TextDocument.uri)

get-editor-from-document : TextDocument.t → IO (Maybe TextEditor.t)
get-editor-from-document doc = do
  docs ← Window.visible-editors >>= mapM λ editor → (editor ,_) <$> TextEditor.document editor
  docs |> find (λ (e , d) → compare-doc doc d) |> fmap Σ.fst |> pure

on-interaction-point? : List InteractionPoint.t → Change.t → Bool
on-interaction-point? ips change = ips
  |> List.any λ ip → Range.equals? (ip .range) (change .source-range)

activate : IO ⊤
activate = try λ _ → do
  output-chan ← OutputChannel.create "Agda Mode"

  extension-context ← ExtensionContext.get
  let keymap-path = Path.join (ExtensionContext.extension-path extension-context ∷ "keymap.json" ∷ [])
  just init-keymap ← load-keymap keymap-path where _ → do
    Window.show-error-message "Failed to read the keymap for the input mode. This is an internal error, please report this." []
    OutputChannel.error ("Failed to read the keymap at the following path: " <> keymap-path) output-chan

  hd-map ← HighlightDecorationMap.init

  model-ref ← init init-keymap >>= IO.Ref.new 
  agda , disposable ← AgdaProcess.spawn output-chan model-ref

  register-command "agda-mode.restart" $ AgdaProcess.restart output-chan model-ref agda

  -- TODO: Register command handlers
  -- TODO: Register disposables
  register-command "agda-mode.load-file" $ do
    just intr ← AgdaInteraction.from-AgdaCommand AgdaCommand.load where _ → pure tt
    TextDocument.save (intr .file)
    AgdaProcess.send-command output-chan intr agda

  forM (StringMap.entries goal-context-cmds) λ (name , cmd) →
    register-command-with-args name λ o → do
      model ← IO.Ref.get model-ref
      just r ← pure $ Rewrite.decoder =<< (just (j-string $ get-rewrite-string o)) where _ → pure tt
      just intr ← AgdaInteraction.under-cursor-command model (cmd r) where _ → pure tt
      AgdaProcess.send-command output-chan intr agda

  forM (StringMap.entries goal-give-cmds) λ (name , cmd) →
    register-command-with-args name λ o → do
      model ← IO.Ref.get model-ref
      just intr ← AgdaInteraction.under-cursor-command model (cmd (get-pmLambda o)) where _ → pure tt
      AgdaProcess.send-command output-chan intr agda

  register-command "agda-mode.make-case" $ do
    model ← IO.Ref.get model-ref
    just intr ← AgdaInteraction.under-cursor-command model AgdaCommand.make-case where _ → pure tt
    AgdaProcess.send-command output-chan intr agda

  register-command "agda-mode.next-goal" $ do
    model ← IO.Ref.get model-ref
    tt <$ jump-to-goal model λ o ips → find ((_> o) ∘ InteractionPoint.cursor-position) ips <|> (ips !! 0)

  register-command "agda-mode.prev-goal" $ do
    model ← IO.Ref.get model-ref
    tt <$ jump-to-goal model λ o ips → find ((_< o) ∘ InteractionPoint.cursor-position) (reverse ips) <|> (reverse ips !! 0)

  forM (StringMap.entries show-general-info-cmds) λ (name , cmd) →
    register-command-with-args name λ o → do
      just r ← pure $ Rewrite.decoder =<< (just (j-string $ get-rewrite-string o)) where _ → pure tt
      just intr ← AgdaInteraction.from-AgdaCommand (cmd r) where _ → pure tt
      AgdaProcess.send-command output-chan intr agda

  register-command "agda-mode.compile-file" $ do
    just backend ← backends !?_ <$> Window.quick-pick (StringMap.keys backends) where _ → pure tt
    just intr ← AgdaInteraction.from-AgdaCommand (AgdaCommand.compile-file backend) where _ → pure tt
    AgdaProcess.send-command output-chan intr agda

  register-command-with-args "agda-mode.compute" λ o → do
    model ← IO.Ref.get model-ref
    just mode ← pure $ ComputeMode.decoder =<< (just (j-string $ get-compute-mode-string o)) where _ → pure tt
    just intr ← (AgdaInteraction.under-cursor-command model (AgdaCommand.compute-goal mode) >>= λ where
      (just intr) → pure (just intr)
      nothing → AgdaInteraction.input-prompt-command (AgdaCommand.compute-toplevel mode)) where _ → pure tt
    AgdaProcess.send-command output-chan intr agda

  register-command-with-args "agda-mode.module-contents" λ o → do
    model ← IO.Ref.get model-ref
    just r ← pure $ Rewrite.decoder =<< (just (j-string $ get-rewrite-string o)) where _ → pure tt
    just intr ← (AgdaInteraction.under-cursor-command model (AgdaCommand.module-contents-goal r) >>= λ where
      (just intr) → pure (just intr)
      nothing → AgdaInteraction.input-prompt-command (AgdaCommand.module-contents-toplevel r)) where _ → pure tt
    AgdaProcess.send-command output-chan intr agda

  register-command "agda-mode.why-in-scope" $ do
    model ← IO.Ref.get model-ref
    just intr ← (AgdaInteraction.under-cursor-command model AgdaCommand.why-in-scope-goal >>= λ where
      (just intr) → pure (just intr)
      nothing → AgdaInteraction.input-prompt-command AgdaCommand.why-in-scope-toplevel) where _ → pure tt
    AgdaProcess.send-command output-chan intr agda

  forM (StringMap.entries toggle-cmds) λ (name , cmd) →
    register-command name $ do
      just intr ← AgdaInteraction.from-AgdaCommand cmd where _ → pure tt
      AgdaProcess.send-command output-chan intr agda

  register-command-with-args "agda-mode.search-about" λ o → do
    model ← IO.Ref.get model-ref
    just r ← pure $ Rewrite.decoder =<< (just (j-string $ get-rewrite-string o)) where _ → pure tt
    just intr ← AgdaInteraction.input-prompt-command (AgdaCommand.search-about-toplevel r) where _ → pure tt
    AgdaProcess.send-command output-chan intr agda

  register-command-with-args "agda-mode.infer" λ o → do
    model ← IO.Ref.get model-ref
    just r ← pure $ Rewrite.decoder =<< (just (j-string $ get-rewrite-string o)) where _ → pure tt
    just intr ← (AgdaInteraction.under-cursor-command model (AgdaCommand.infer r) >>= λ where
      (just intr) → pure (just intr)
      nothing → AgdaInteraction.input-prompt-command (AgdaCommand.infer-toplevel r)) where _ → pure tt
    AgdaProcess.send-command output-chan intr agda

  model ← IO.Ref.get model-ref
  stp ← SemanticTokensProvider.new
    (just (EventEmitter.event $ model .tokens-request-emitter))
    λ doc token → agda .response-queue |> JobQueue.await-push (do
      model ← IO.Ref.get model-ref
      case model .loaded-files !? TextDocument.file-name doc of λ where
        (just (mkFile ips tokens)) → do
          get-editor-from-document doc >>= maybe (pure tt) λ e → do
            apply-decorations hd-map e tokens
            let ranges = map InteractionPoint.range ips
            TextEditor.set-decoration (model .ip-decoration) ranges e
          apply-semantic-tokens doc tokens
        nothing → throw "Busy")
      
  SemanticTokensProvider.register (language "agda" ∩ scheme "file") stp DefaultLegend

  DefinitionProvider.register (language "agda" ∩ scheme "file") =<<
    DefinitionProvider.new λ doc pos tok → agda .response-queue |> JobQueue.await-push (do
      model ← IO.Ref.get model-ref
      from-Maybe (pure nothing) $ do
        mkFile ips tokens ← model .loaded-files !? TextDocument.file-name doc
        token ← find (Range.contains? pos ∘ Token.range) tokens
        site ← token .definition-site
        just $ do
          other ← TextDocument.open-path (site .filepath)
          let pos = TextDocument.position-at other (site .position - 1)
          pure (just $ Location.new (TextDocument.uri other) pos))

  HoverProvider.register (language "agda" ∩ scheme "file") λ doc pos tok → do
    model ← IO.Ref.get model-ref
    pure $ do
      mkFile ips tokens ← model .loaded-files !? TextDocument.file-name doc
      token ← find (Range.contains? pos ∘ Token.range) tokens
      token .note |> λ where
        "" → nothing
        note → just (mkHover [ MarkdownString.new note ] (just (token .range)))

  register-change-handler agda model-ref

  input-mode-model ← IO.Ref.new $ InputMode.Model ∋ nothing
  let uim x = do IO.Ref.get model-ref >>= λ model → update-input-mode (model .keymap) (model .underline-decoration) (model .input-mode-status-item) input-mode-model x
  register-command "agda-mode.backspace" $ uim InputMode.backspace
  register-command "agda-mode.arrow-left" $ uim InputMode.left
  register-command "agda-mode.arrow-right" $ uim InputMode.right
  register-command "agda-mode.escape" $ uim InputMode.escape
  register-command "agda-mode.tab" $ uim InputMode.tab
  register-command-with-args "type" λ args →
    required "text" (InputMode.character <$> string) args |> maybe (pure tt) uim

  trace "Started extensionn"

  pure tt
