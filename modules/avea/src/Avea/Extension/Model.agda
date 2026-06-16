module Avea.Extension.Model where

open import Agda.Builtin.Unit

open import Data.Maybe
open import Data.Maybe.Effectful
open import Data.String
import Data.String as String
open import Data.Map
open import Data.List hiding (_++_ ; head)
open import Data.Product
open import Data.Nat
import Data.Nat as Nat
open import Data.Bool
open import Function hiding (id)
open import Data.IO
open import Data.JSON.Decode
open import Effect.Monad

open Monad {{ ... }}
open MonadPlus {{ ... }} using (_<|>_ ; ⊘)

open import Avea.Extension.Highlighting
open import Avea.Extension.Highlighting.Decode hiding (range-decoder)
open import Avea.Extension.Keymap

open import Vscode.Panel
open import Vscode.Window
open import Vscode.Common
open import Vscode.SemanticTokensProvider
open import Vscode.TextEditor

open import Node.Process

open import Class.Show

module InteractionPoint where
  record t : Set where
    constructor mkInteractionPoint
    field
      id : Nat
      range : Range.t
  open t public

  content-range : Range.t → Range.t
  content-range range = -- offset-range (range .start + 2) (range .length - 4)
    Range.new (Position.right 2 $ Range.start range) (Position.left 2 $ Range.end range)

  equals? : t → t → Bool
  equals? a b = Range.equals? (a .range) (b .range) ∧ a .id Nat.== b .id

  start-marker end-marker : t → Range.t
  start-marker ip =
    let ip-start = Range.start $ ip .range in
    Range.new ip-start (Position.right 2 $ ip-start)
  end-marker ip =
    let ip-end = Range.end $ ip .range in
    Range.new (Position.left 2 $ ip-end) ip-end

  cursor-position : t → Position.t
  cursor-position = Position.right 3 ∘ Range.start ∘ range

  pos-decoder : Decoder Position.t
  pos-decoder = do
    line ← required "line" nat
    col ← required "col" nat
    pure $ Position.new (line - 1) (col - 1)

  range-decoder : Decoder Range.t
  range-decoder = do
    start ← required "start" pos-decoder
    end ← required "end" pos-decoder
    pure $ Range.new start end

  decoder : Decoder (TextDocument.t → t)
  decoder = do
    id ← required "id" nat
    range ← list range-decoder |> index 0 |> required "range"
    pure λ doc → mkInteractionPoint id range
open InteractionPoint using (mkInteractionPoint ; id ; range) public

instance
  Show-InteractionPoint : Show InteractionPoint.t
  Show-InteractionPoint = record
    { show = λ where
      (mkInteractionPoint id range) →
        "mkInteractionPoint " ++ show id ++ " " ++ show range
    }

record File : Set where
  constructor mkFile
  field
    interaction-points : List InteractionPoint.t
    tokens : List Token.t
open File public

record Model : Set where field
  panel : Maybe (Panel.t ⊤)
  status-bar-item : StatusBarItem.t
  input-mode-status-item : StatusBarItem.t
  agda : Maybe Process.t
  stdout-buffer : String
  current-doc : Maybe TextDocument.t
  loaded-files : StringMap.t File
  tokens-request-emitter : EventEmitter.t ⊤
  running-info : String
  underline-decoration ip-decoration : DecorationType.t
  keymap : Trie.t
open Model public

module Rewrite where
  data t : Set where
    as-is instantiated head-normal simplified normalised : t

  show' : t → String
  show' as-is = "AsIs"
  show' instantiated = "Instantiated"
  show' head-normal = "HeadNormal"
  show' simplified = "Simplified"
  show' normalised = "Normalised"

  instance
    Show-Rewrite : Show t
    Show-Rewrite = record { show = show' }

  decoder : Decoder t
  decoder = string >>= λ where
    "AsIs" → succeed as-is
    "Instantiated" → succeed instantiated
    "HeadNormal" → succeed head-normal
    "Simplified" → succeed simplified
    "Normalised" → succeed normalised
    _ → ⊘
open Rewrite hiding (t ; decoder ; show') public

module Backend where
  data t : Set where
    ghc : Bool → t
    js html latex quicklatex : t

  show' : t → String
  show' (ghc main?) = if main? then "GHC" else "GHC (no main)" 
  show' js = "JS"
  show' html = "HTML"
  show' latex = "LaTeX"
  show' quicklatex = "QuickLaTeX"

  instance
    Show-Backend : Show t
    Show-Backend = record { show = show' }

  encode : t → String
  encode (ghc main?) = if main? then "GHC" else "GHCNoMain"
  encode t = show t
open Backend using (ghc ; js ; html ; latex ; quicklatex) public

module ComputeMode where
  data t : Set where
    default head ignore-abstract use-show-instance : t

  decoder : Decoder t
  decoder = string >>= λ where
    "DefaultCompute" → succeed default
    "HeadCompute" → succeed head
    "IgnoreAbstract" → succeed ignore-abstract
    "UseShowInstance" → succeed use-show-instance
    _ → ⊘

  show' : t → String
  show' default = "DefaultCompute"
  show' head = "HeadCompute"
  show' ignore-abstract = "IgnoreAbstract"
  show' use-show-instance = "UseShowInstance"

  instance
    Show-ComputeMode : Show t
    Show-ComputeMode = record { show = show' }

module AgdaCommand where
  data t : Set where
    load : t
    -- Give uses the boolean to indicate whether force should be used,
    -- refine uses the boolean to indicate whether the compiler should create case lambdas when intro'ing functions
    give refine-or-intro : Bool → InteractionPoint.t → t
    context goal-type infer goal-type-context goal-type-context-infer
      goal-type-context-check auto-goal module-contents-goal
        : Rewrite.t → InteractionPoint.t → t
    show-metas show-constraints : Rewrite.t → t
    make-case why-in-scope-goal : InteractionPoint.t → t
    compile-file : Backend.t → t
    compute-goal : ComputeMode.t → InteractionPoint.t → t
    compute-toplevel : ComputeMode.t → String → t
    module-contents-toplevel search-about-toplevel infer-toplevel : Rewrite.t → String → t
    why-in-scope-toplevel : String → t
    toggle-hidden toggle-irrelevant : t

  show-pos : Position.t → TextDocument.t → String
  show-pos pos doc =
    let offset = TextDocument.offset-at doc pos
     in "Pn () " ++ show (offset + 1) ++ " " ++ show (Position.line pos) ++ " " ++ show (Position.char pos)

  show-range : TextDocument.t → Range.t → String
  show-range doc range =
    let start = Range.start range in
    let end = Range.end range in
    let range = "Interval () (" ++ show-pos start doc ++ ") (" ++ show-pos end doc ++ ")"
     in "intervalsToRange Nothing [" ++ range ++ "]"

  show-goal-command : TextDocument.t → InteractionPoint.t → List String
  show-goal-command doc ip = 
    let goal-content = doc |> TextDocument.get-text (InteractionPoint.content-range (ip .range)) in
    let sanitised-goal-content = replace "\"" "\\\"" goal-content in

    -- We send along an up-to-date version of the interaction point's range.
    -- Agda uses this range to update its internal state, and return a correct range when responding with a
    -- give action. This means we can fully rely on the new locations provided by Agda without consulting
    -- our own cache again.
    --
    -- NOTE: There does seem to be a bug/inconsistency in the compiler when sending the range including markers,
    -- where the locations of errors within the hole are reported incorrectly in the display infos.
    show (ip .id) ∷ ("(" ++ show-range doc (ip .range) ++ ")") ∷ ("\"" ++ sanitised-goal-content ++ "\"") ∷ []

  show-goal-rewrite-command : TextDocument.t → Rewrite.t → InteractionPoint.t → List String
  show-goal-rewrite-command doc r ip = show r ∷ show-goal-command doc ip

  show-list : TextDocument.t → t → List String
  show-list doc load = "Cmd_load" ∷ "\"" ++ TextDocument.file-name doc ++ "\"" ∷ "[]" ∷ []
  show-list doc (give with-force ip) =
    let force = if with-force then "WithForce" else "WithoutForce" in
    "Cmd_give" ∷ force ∷ show-goal-command doc ip
  show-list doc (refine-or-intro b ip) =
    let b' = if b then "True" else "False" in
    "Cmd_refine_or_intro" ∷ b' ∷ show-goal-command doc ip
  show-list doc (context r ip) = "Cmd_context" ∷ show-goal-rewrite-command doc r ip
  show-list doc (goal-type r ip) = "Cmd_goal_type" ∷ show-goal-rewrite-command doc r ip
  show-list doc (infer r ip) = "Cmd_infer" ∷ show-goal-rewrite-command doc r ip
  show-list doc (goal-type-context r ip) = "Cmd_goal_type_context" ∷ show-goal-rewrite-command doc r ip
  show-list doc (goal-type-context-infer r ip) = "Cmd_goal_type_context_infer" ∷ show-goal-rewrite-command doc r ip
  show-list doc (goal-type-context-check r ip) = "Cmd_goal_type_context_check" ∷ show-goal-rewrite-command doc r ip
  show-list doc (auto-goal r ip) = "Cmd_autoOne" ∷ show-goal-rewrite-command doc r ip
  show-list doc (module-contents-goal r ip) = "Cmd_show_module_contents" ∷ show-goal-rewrite-command doc r ip
  show-list doc (show-constraints r) = "Cmd_constraints" ∷ show r ∷ []
  show-list doc (show-metas r) = "Cmd_metas" ∷ show r ∷ []
  show-list doc (make-case ip) = "Cmd_make_case" ∷ show-goal-command doc ip
  show-list doc (why-in-scope-goal ip) = "Cmd_why_in_scope" ∷ show-goal-command doc ip
  show-list doc (compile-file backend) = "Cmd_compile" ∷ Backend.encode backend ∷ ("\"" ++ TextDocument.file-name doc ++ "\"") ∷ "[]" ∷ []
  show-list doc (compute-goal mode ip) = "Cmd_compute" ∷ show mode ∷ show-goal-command doc ip
  show-list doc (compute-toplevel mode term) = "Cmd_compute_toplevel" ∷ show mode ∷ ("\"" ++ term ++ "\"") ∷ []
  show-list doc (module-contents-toplevel r name) = "Cmd_show_module_contents_toplevel" ∷ show r ∷ ("\"" ++ name ++ "\"") ∷ []
  show-list doc (infer-toplevel r term) = "Cmd_infer_toplevel" ∷ show r ∷ ("\"" ++ term ++ "\"") ∷ []
  show-list doc (search-about-toplevel r query) = "Cmd_search_about_toplevel" ∷ show r ∷ ("\"" ++ query ++ "\"") ∷ []
  show-list doc (why-in-scope-toplevel term) = "Cmd_why_in_scope_toplevel" ∷ ("\"" ++ term ++ "\"") ∷ []
  show-list doc toggle-hidden = "ToggleImplicitArgs" ∷ []
  show-list doc toggle-irrelevant = "ToggleIrrelevantArgs" ∷ []

  serialise : TextDocument.t → t → String
  serialise = intercalate " " ∘₂ show-list

module AgdaInteraction where
  record t : Set where
    constructor iotcm
    field
      file : TextDocument.t
      command : AgdaCommand.t
  open t public

  show' : t → String
  show' (iotcm file cmd) =
    let path = TextDocument.file-name file in
    "IOTCM \"" ++ path ++ "\" NonInteractive Direct (" ++ AgdaCommand.serialise file cmd ++ ")\n"

  instance
    Show-AgdaInteraction : Show t
    Show-AgdaInteraction = record { show = show' }

  from-AgdaCommand : AgdaCommand.t → IO (Maybe t)
  from-AgdaCommand cmd = do
    just e ← TextEditor.active-editor where _ → pure nothing
    doc ← TextEditor.document e
    pure $ just (iotcm doc cmd)

  under-cursor-command : Model → (InteractionPoint.t → AgdaCommand.t) → IO (Maybe t)
  under-cursor-command model cmd = do
    just e ← TextEditor.active-editor where _ → pure nothing
    doc ← TextEditor.document e
    cursor ← TextEditor.cursor-pos e
    model .loaded-files !? TextDocument.file-name doc |> maybe (pure nothing) λ (record { interaction-points = ips }) → do
     ips |> find (λ ip → Range.contains? cursor (ip .range)) |> maybe (pure nothing) λ ip → do
      pure $ just (iotcm doc (cmd ip))

  input-prompt-command : (String → AgdaCommand.t) → IO (Maybe t)
  input-prompt-command cmd = do
    just e ← TextEditor.active-editor where _ → pure nothing
    doc ← TextEditor.document e
    input ← from-Maybe "" <$> Window.show-input-box
    pure $ just (iotcm doc (cmd input))
    
open AgdaInteraction using (iotcm ; file ; command) public

module Config where
  record t : Set where
    constructor mkConfig
    field
      agda-path : Maybe String
      extra-args : String
      versions : List String
  open t public

  decoder : Decoder t
  decoder = do
    path ← required "agda-path" string <&> λ s → if s String.== "" then nothing else just s
    (| (mkConfig path) (required "extra-args" string) (required "agda-versions" (list string)) |)

  postulate invalid : {A : Set} → IO A
  {-# COMPILE JS invalid = A => async () => { throw "call to invalid" } #-}

  load : IO t
  load = do
    just config ← decoder ∘ WorkspaceConfiguration.as-JSON <$> Workspace.get-configuration "avea"
      where _ → invalid -- TODO: Show an error to the user
    pure config
open Config using (agda-path ; extra-args) public
