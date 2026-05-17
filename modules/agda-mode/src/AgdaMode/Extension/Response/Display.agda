module AgdaMode.Extension.Response.Display where

open import Data.String hiding (show)
open import Data.Nat hiding (show ; _==_) ; import Data.Nat as Nat
open import Data.Int hiding (pos ; _+_)
open import Data.IO
import Data.IO as IO
open import Data.List hiding (any ; head) renaming (_++_ to _++ˡ_)
import Data.List as List
open import Data.Maybe
open import Data.Maybe.Effectful
open import Data.Map
open import Data.Bool
open import Data.String renaming (∥_∥ to ∥_∥ˢ ; slice to sliceˢ) hiding (show)
open import Data.JSON
open import Data.Product
open import Data.JSON.Decode
open import Agda.Builtin.Unit
open import Agda.Builtin.Char

open import Function hiding (id)
open import Level

open import AgdaMode.Extension.Highlighting
open import AgdaMode.Extension.Highlighting.Decode
open import AgdaMode.Extension.Model
open import AgdaMode.Extension.Position

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

record ConstraintPosition : Set where
  constructor mkPosition
  field col line pos : Nat

position-decoder : Decoder ConstraintPosition
position-decoder = mkPosition
  <$> required "col" nat
  <*> required "line" nat
  <*> required "pos" nat

-- TODO: Isn't this just equivalent to Range.t?
record ConstraintRange : Set where
  constructor mkRange
  field start end : ConstraintPosition

range-decoder : Decoder ConstraintRange
range-decoder = mkRange
  <$> required "start" position-decoder
  <*> required "end" position-decoder

record Constraint : Set where
  constructor mkConstraint
  field
    id' : Nat
    range : List ConstraintRange

constraint-decoder : Decoder Constraint
constraint-decoder = mkConstraint
  <$> required "id" nat
  <*> required "range" (list range-decoder)

record Goal : Set where
  constructor mkGoal
  field
    constraint : Constraint
    type : String

show-goal : Goal → String
show-goal (mkGoal (mkConstraint name _) type) = "?" ++ Nat.show name ++ " : " ++ type

goal-decoder : Decoder Goal
goal-decoder = mkGoal
  <$> required "constraintObj" constraint-decoder
  <*> required "type" string

record InvisibleConstraint : Set where
  constructor mkInvisibleConstraint
  field
    name : String
    range : List ConstraintRange
open InvisibleConstraint

invisible-constraint-decoder : Decoder InvisibleConstraint
invisible-constraint-decoder = mkInvisibleConstraint
  <$> required "name" string
  <*> required "range" (list range-decoder)

record InvisibleGoal : Set where
  constructor mkInvisibleGoal
  field
    constraint : InvisibleConstraint
    kind type : String
open InvisibleGoal

show-invisible-goal : InvisibleGoal → String
show-invisible-goal (mkInvisibleGoal constraint kind type) = constraint .name ++ " : " ++ type

invisible-goal-decoder : Decoder InvisibleGoal
invisible-goal-decoder = mkInvisibleGoal
  <$> required "constraintObj" invisible-constraint-decoder
  <*> required "kind" string
  <*> required "type" string

record ContextItem : Set where
  constructor mkContextItem
  field
    binding original-name reified-name : String
    in-scope? : Bool
open ContextItem

context-item-decoder : Decoder ContextItem
context-item-decoder = ⦇ mkContextItem
  (required "binding" string)
  (required "originalName" string)
  (required "reifiedName" string)
  (required "inScope" bool) ⦈

show-context-item : ContextItem → String
show-context-item item = item .original-name ++ " : " ++ item .binding ++ (if item .in-scope? then "" else " (not in scope)")

record Context : Set where
  constructor mkContext
  field
    context-items : List ContextItem
    interaction-point : InteractionPoint.t
open Context

show-context : Context → String
show-context ctx = ctx .context-items
  |> map show-context-item
  |> intercalate "\n"

data TypeAux : Set where
  goal-only : TypeAux
  goal-and-have : String → TypeAux
  goal-and-elaboration : String → TypeAux

type-aux-decoder : Decoder TypeAux
type-aux-decoder = required "kind" string >>= λ where
  "GoalOnly" → succeed goal-only
  "GoalAndHave" → goal-and-have <$> required "expr" string
  "GoalAndElaboration" → goal-and-elaboration <$> required "term" string
  _ → ⊘

show-aux : TypeAux → String
show-aux goal-only = ""
show-aux (goal-and-have expr) = "\nHave: " ++ expr
show-aux (goal-and-elaboration expr) = "\nElaborated: " ++ expr

module GoalInfo where
  data t : Set where
    inferred-type : String → t
    current-goal : Rewrite.t → String → t
    normal-form : ComputeMode.t → String → t
    goal-type : Maybe (List ContextItem) → String → TypeAux → t

  decoder : Decoder t
  decoder = required "kind" string >>= λ where
    "InferredType" → (| inferred-type (required "expr" string) |)
    "CurrentGoal" → (| current-goal (required "rewrite" Rewrite.decoder) (required "type" string) |)
    "GoalType" → (| goal-type (optional "entries" (list context-item-decoder)) (required "type" string) (required "typeAux" type-aux-decoder) |)
    "NormalForm" → (| normal-form (required "computeMode" ComputeMode.decoder) (required "expr" string) |)
    _ → ⊘

module ModuleContents where
  record t : Set where
    constructor mkModuleContents
    field
      names : List String
      contents : List (String × String)
      -- TODO: telescope
  open t public

  contents-item-decoder : Decoder (String × String)
  contents-item-decoder = (| required "name" string , required "term" string |)

  decoder : Decoder t
  decoder = (| mkModuleContents (required "names" (list string)) (required "contents" (list contents-item-decoder)) |)

open ModuleContents using (mkModuleContents ; names ; contents) public

data DisplayInfo : Set where
  all-goals-warnings :
    (errors : List String)
    (invisible-goals : List InvisibleGoal)
    (visible-goals : List Goal)
    (warnings : List String) → DisplayInfo
  error : (error-message : String) → (warnings : List String) → DisplayInfo
  why-in-scope normal-form inferred-type : String → DisplayInfo
  context : Context → DisplayInfo
  -- goal-info : InteractionPoint.t → GoalInfo → DisplayInfo
  intro-not-found : DisplayInfo
  goal-specific : GoalInfo.t → InteractionPoint.t → DisplayInfo
  module-contents : ModuleContents.t → DisplayInfo
  search-about : String → List (String × String) → DisplayInfo

error-decoder : Decoder String
error-decoder = required "message" string

context-decoder : Decoder Context
context-decoder = mkContext
  <$> required "context" (list context-item-decoder)
  <*> required "interactionPoint" InteractionPoint.decoder

data OutputConstraint : Set where
  of-type : (constraint-obj type : String) → OutputConstraint
  cmp-in-type : (comparison type lhs rhs : String) → OutputConstraint
  cmp-elim : (polarities : List String) (type : String) (lhs rhs : List String) → OutputConstraint
  just-type just-sort : (constraint-obj : String) → OutputConstraint
  cmp-types cmp-levels cmp-teles cmp-sorts : (comparison lhs rhs : String) → OutputConstraint
  assign : (constraint-obj value : String) → OutputConstraint
  typed-assign : (constraint-obj value type : String) → OutputConstraint
  postponed-check-args : (constraint-obj of-type type : String) (arguments : List String) → OutputConstraint
  is-empty-type size-lt-sat : (type : String) → OutputConstraint
  find-instance-of : (constraint-obj type : String) (candidates : List (String × String)) → OutputConstraint
  resolve-instance-of : (name : String) → OutputConstraint
  pts-instance : (lhs rhs : String) → OutputConstraint
  postponed-check-fun-def : (name type error : String) → OutputConstraint
  data-sort : (name sort : String) → OutputConstraint
  check-lock : (head lock : String) → OutputConstraint
  usable-at-mod : (mod term : String) → OutputConstraint

pair-decoder : Decoder A → Decoder (A × A)
pair-decoder d = ⦇ index 0 (list d) , index 1 (list d) ⦈

cmp-decoder : (String → String → String → OutputConstraint) → Decoder OutputConstraint
cmp-decoder c = ⦇ uncurry ⦇ c (required "comparison" string) ⦈ (required "constraintObjs" (pair-decoder string)) ⦈

output-constraint-decoder : Decoder OutputConstraint
output-constraint-decoder = required "kind" string >>= λ where
  "OfType" → ⦇ of-type (required "constraintObj" string) (required "type" string) ⦈
  "CmpInType" → ⦇ uncurry ⦇ cmp-in-type (required "comparison" string) (required "type" string) ⦈
                          (required "constraintObjs" (pair-decoder string)) ⦈
  "CmpElim" → ⦇ uncurry ⦇ cmp-elim (required "polarities" (list string)) (required "type" string) ⦈
                        (required "constraintObjs" (pair-decoder $ list string)) ⦈
  "JustType" → ⦇ just-type (required "constraintObj" string) ⦈
  "JustSort" → ⦇ just-sort (required "constraintObj" string) ⦈
  "CmpTypes" → cmp-decoder cmp-types ; "CmpLevels" → cmp-decoder cmp-levels
  "CmpTeles" → cmp-decoder cmp-teles ; "CmpSorts" → cmp-decoder cmp-sorts
  _ → ⊘

display-info-decoder : Decoder DisplayInfo
display-info-decoder = do
  "DisplayInfo" ← required "kind" string where _ → ⊘
  required "info" $
    required "kind" string >>= λ where
      "AllGoalsWarnings" → all-goals-warnings
        <$> required "errors" (list error-decoder)
        <*> required "invisibleGoals" (list invisible-goal-decoder)
        <*> required "visibleGoals" (list goal-decoder)
        <*> required "warnings" (list error-decoder)
      "Error" → (| error (required "error" (required "message" string)) (required "warnings" (list (required "message" string))) |)
      "Context" → context <$> context-decoder
      "GoalSpecific" → goal-specific
        <$> required "goalInfo" GoalInfo.decoder
        <*> required "interactionPoint" InteractionPoint.decoder
      "IntroNotFound" → succeed intro-not-found
      "ModuleContents" → (| module-contents ModuleContents.decoder |)
      "WhyInScope" → (| why-in-scope (required "message" string) |)
      "SearchAbout" →
        let results-decoder = (| required "name" string , required "term" string |) in
        (| search-about (required "search" string) (required "results" (list results-decoder)) |)
      "NormalForm" → (| normal-form (required "expr" string) |)
      "InferredType" → (| inferred-type (required "expr" string) |)
      _ → ⊘

_when'_ : A → Bool → List A
a when' true = [ a ]
a when' false = []

show-display-info : DisplayInfo → String
show-display-info (all-goals-warnings errors inv vis warns) =
  let content = 
        unlines $
                    ("---------- Goals ----------" when' not (null? vis))
          ⟨ append ⟩ (map show-goal vis)
          ⟨ append ⟩ (map show-invisible-goal inv)
          ⟨ append ⟩ ("\n---------- Errors ----------" when' not (null? errors))
          ⟨ append ⟩ errors
          ⟨ append ⟩ ("\n---------- Warnings ----------\n" when' not (null? warns))
          ⟨ append ⟩ warns
   in if content == "" then "All good." else content
show-display-info (error error-message warnings) =
  "---------- Error ----------\n" ++ error-message ++
  "\n\n---------- Warnings ----------\n" ++ intercalate "\n\n" (append warnings warnings)
show-display-info (context ctx) = show-context ctx
show-display-info (goal-specific (GoalInfo.inferred-type type) ip) = type
show-display-info (goal-specific (GoalInfo.normal-form _ nf) ip) = nf
show-display-info (goal-specific (GoalInfo.current-goal _ type) ip) =
  "?" ++ Nat.show (ip .id) ++ " : " ++ type
show-display-info (goal-specific (GoalInfo.goal-type entries type aux) ip) =
  let context-info = entries |> maybe "" (("\n---------- Context ----------\n" ++_) ∘ intercalate "\n" ∘ map show-context-item) in
  let aux-info = show-aux aux in
  "Goal: " ++ type ++ aux-info ++ context-info
show-display-info intro-not-found = "No introduction forms found."
show-display-info (module-contents (mkModuleContents names contents)) =
  "Modules\n" ++ intercalate "\n" (map ("  " ++_) names) ++
    "\nNames\n" ++ intercalate "\n" (map (λ (name , term) → "  " ++ name ++ " : " ++ term) contents)
show-display-info (why-in-scope message) = message
show-display-info (search-about query results) =
  let show-result (name , term) = "  " ++ name ++ " : " ++ term in
  "Definitions about " ++ query ++ "\n" ++ intercalate "\n" (map show-result results)
show-display-info (normal-form message) = message
show-display-info (inferred-type message) = message

open import Agda.Builtin.Equality

instance
  cloneable-⊤ : Cloneable ⊤
  cloneable-⊤ = record
    { encode = λ _ → j-null
    ; decode = λ { j-null → just tt ; _ → nothing }
    ; encode-decode-dual = λ { tt → refl }
    }

new-panel : Ref.t Model → IO (Panel.t ⊤)
new-panel model-ref = do
  panel ← Panel.create
    "agdaMode-buffer"
    "*Agda information*"
    (record { preserve-focus = true ; view-column = ViewColumn.three })
    WebviewOptions.default
  Panel.on-did-dispose (do
    model-ref |> Ref.modify λ model → record model { panel = nothing }
    pure tt) panel
  pure panel

handle-display-info : Ref.t Model → Model → DisplayInfo → IO Model
handle-display-info model-ref model display-info = do
  panel ← from-Maybe (new-panel model-ref) (pure <$> model .panel)
  Panel.set-html panel ("<pre>" ++ show-display-info display-info ++ "</pre>")
  pure record model { panel = just panel }