module Avea.Extension.Response where

open import Data.String
open import Data.Nat hiding (_==_) ; import Data.Nat as Nat
open import Data.Int hiding (pos ; _+_)
open import Data.IO
import Data.IO as IO
open import Data.List hiding (any ; head) renaming (_++_ to _++ˡ_)
import Data.List as List
open import Data.Maybe
open import Data.Maybe.Effectful
open import Data.Map
open import Data.Bool
open import Data.String renaming (∥_∥ to ∥_∥ˢ ; slice to sliceˢ)
open import Data.JSON
open import Data.Product
open import Data.JSON.Decode
open import Agda.Builtin.Unit
open import Agda.Builtin.Char
open import Class.Show

open import Function hiding (id)
open import Level

open import Avea.Extension.Highlighting
open import Avea.Extension.Highlighting.Decode
open import Avea.Extension.Model
open import Avea.Extension.Response.Display
open import Avea.Extension.Response.Goal

open import Vscode.Window
open import Vscode.Panel
open import Vscode.Common
open import Vscode.TextEditor
open import Vscode.SemanticTokensProvider

open import Effect.Monad

open Monad ⦃ ... ⦄
open MonadPlus ⦃ ... ⦄ using (⊘ ; _<|>_)

private variable
  a : Level
  A : Set a


private
  postulate trace : {A : Set} → A → IO ⊤
  {-# COMPILE JS trace = A => a => async () => { console.log(a); return b => b["tt"]() } #-}

kind-decoder : Decoder String
kind-decoder = required "kind" string

parse-response : String → Maybe JSON
parse-response response = do
  let truncated-response = if (response starts-with "JSON> ") then sliceˢ 6 ∥ response ∥ˢ response else response
  parse-json truncated-response

handle-highlighting-info : Model → (TextDocument.t → List Token.t × Bool) → IO Model
handle-highlighting-info model f = do
  just e ← TextEditor.active-editor where _ → pure model
  doc ← TextEditor.document e
  let token-list , remove = f doc

  m ← model .loaded-files !? TextDocument.file-name doc |> λ where
    nothing → pure record model
      { loaded-files = model .loaded-files [ TextDocument.file-name doc ]:= mkFile [] (sort-Ord token-list)
      }
    (just file) → pure record model
      { loaded-files = model .loaded-files [ TextDocument.file-name doc ]:=
          record file { tokens = sort-Ord (if remove then token-list else file .tokens ++ˡ token-list) }
      }
  
  EventEmitter.fire (model .tokens-request-emitter) tt
  
  pure m

clear-highlighting-decoder : Decoder ⊤
clear-highlighting-decoder =
  required "kind" string >>= λ where
    "ClearHighlighting" → pure tt
    _ → ⊘

handle-clear-highlighting : Model → ⊤ → IO Model
handle-clear-highlighting model tt = do
  just e ← TextEditor.active-editor where _ → pure model
  doc ← TextEditor.document e
  pure record model
    { loaded-files = model .loaded-files [ TextDocument.file-name doc ]:= mkFile [] []
    }

record Status : Set where
  constructor mkStatus
  field checked show-implicit show-irrelevant : Bool
open Status

show-status : Status → String
show-status status = intercalate ", " $
             ("Checked" when' status .checked)
  ⟨ append ⟩ ("ShowImpl" when' status .show-implicit)
  ⟨ append ⟩ ("ShowIrr" when' status .show-irrelevant)

status-decoder : Decoder Status
status-decoder = do
  "Status" ← required "kind" string where _ → ⊘
  required "status" $ mkStatus
    <$> required "checked" bool
    <*> required "showImplicitArguments" bool
    <*> required "showIrrelevantArguments" bool

handle-status : Model → Status → IO Model
handle-status model status = do
  StatusBarItem.set-text (model .status-bar-item) (show-status status)
  StatusBarItem.show (model .status-bar-item)
  pure model

clear-running-info-decoder : Decoder ⊤
clear-running-info-decoder = required "kind" string >>= λ where
  "ClearRunningInfo" → pure tt ; _ → ⊘

handle-clear-running-info : Ref.t Model → Model → ⊤ → IO Model
handle-clear-running-info model-ref model tt = do
  panel ← from-Maybe (new-panel model-ref) (pure <$> model .panel)
  Panel.set-html panel ""
  pure record model { panel = just panel ; running-info = "" }

record RunningInfo : Set where
  constructor mkRunningInfo
  field
    debug-level : Nat
    message : String
open RunningInfo

running-info-decoder : Decoder RunningInfo
running-info-decoder = do
  "RunningInfo" ← required "kind" string where _ → ⊘
  (| mkRunningInfo (required "debugLevel" nat) (required "message" string) |)

handle-running-info : Ref.t Model → Model → RunningInfo → IO Model
handle-running-info model-ref model info = do
  panel ← from-Maybe (new-panel model-ref) (pure <$> model .panel)
  -- TODO: Allow configuration of debug level
  let new-running-info = model .running-info ++ info .message ++ "\n"
  Panel.set-html panel $ "<pre>" ++ new-running-info ++ "</pre>"
  pure record model { panel = just panel ; running-info = new-running-info }

record JumpToError : Set where
  constructor mkJumpToError
  field
    file-path : String
    position : Nat
open JumpToError

jump-to-error-decoder : Decoder JumpToError
jump-to-error-decoder = do
  "JumpToError" ← required "kind" string where _ → ⊘
  (| mkJumpToError (required "filepath" string) (required "position" nat) |)

handle-jump-to-error : Model → JumpToError → IO Model
handle-jump-to-error model jump-to-error = do
  doc ← TextDocument.open-path (jump-to-error .file-path)
  let uri = TextDocument.uri doc
  let pos = TextDocument.position-at doc (jump-to-error .position)
  Window.show-text-document uri record
    { preserve-focus = true
    ; preview = true
    ; selection = Range.new pos pos
    ; view-column = ViewColumn.active
    }
  pure model

-- TODO: Change this to have type Decoder (Model → IO Model)
handle-agda-message : (AgdaInteraction.t → IO ⊤) → Ref.t Model → Model → Decoder (IO Model)
handle-agda-message send-command model-ref model =
  (| (handle-highlighting-info model) highlighting-info-decoder
   | (handle-clear-highlighting model) clear-highlighting-decoder
   | (handle-display-info model-ref model) display-info-decoder
   | (handle-status model) status-decoder
   | (handle-clear-running-info model-ref model) clear-running-info-decoder
   | (handle-running-info model-ref model) running-info-decoder
   | (handle-jump-to-error model) jump-to-error-decoder
   | (handle-interaction-points model) interaction-points-decoder
   | (handle-give-action send-command model) give-action-decoder
   | (handle-make-case send-command model) make-case-decoder
   | (λ x → trace x >> pure model) any
   |)
