module Avea.Extension.Response.Goal where

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
open import Data.String renaming (∥_∥ to ∥_∥ˢ ; slice to sliceˢ) hiding (_==_)
import Data.String as String
open import Data.JSON
open import Data.Product
open import Data.JSON.Decode
open import Agda.Builtin.Unit
open import Agda.Builtin.Char

open import Function hiding (id)
open import Level

open import Avea.Extension.Highlighting
open import Avea.Extension.Highlighting.Decode
open import Avea.Extension.Model

open import Vscode.Window
open import Vscode.Panel
open import Vscode.Common
open import Vscode.TextEditor
open import Vscode.SemanticTokensProvider

open import Effect.Monad

open import Class.Show
open import Class.Monoid

open Monad ⦃ ... ⦄
open MonadPlus ⦃ ... ⦄ using (⊘ ; _<|>_)

private variable
  a : Level
  A : Set a

single-character-range? : Range.t → Bool
single-character-range? r =
  (Position.line $ Range.start r) Nat.== (Position.line $ Range.end r)
  ∧ (1 + Position.char (Range.start r)) Nat.== (Position.char $ Range.end r)

-- TODO: The order of the interaction point list does not matter, so we might as well cons the ips instead of
-- inefficiently snoc'ing them.
expand-interaction-point : List InteractionPoint.t × Nat → InteractionPoint.t → List InteractionPoint.t × Nat
expand-interaction-point (ac , Δ) ip =
  if not (single-character-range? (ip .range)) then
    ac <> [ ip ] , Δ
  else (
    let shifted-range = Range.new (Position.right Δ (Range.start $ ip .range)) (Position.right (Δ + 6) (Range.start $ ip .range)) in
    ac <> [ record ip { range = shifted-range } ] , Δ + 5 
  )

-- This function only merges 1-wide interaction points with old interactions points. It should not occur that
-- interactions overlap in any other way.
merge-ip : List InteractionPoint.t → InteractionPoint.t → InteractionPoint.t
merge-ip old-ips ip =
  let old-ip = find (λ expanded-ip → Range.contains? (Range.start $ ip .range) (expanded-ip .range) ) old-ips in
  (single-character-range? (ip .range) , old-ip) |> λ where
    (true , just old-ip) → old-ip
    (_ , _) → ip

private
  postulate trace : {A : Set} → A → IO ⊤
  {-# COMPILE JS trace = A => a => async () => { console.log(a); return b => b["tt"]() } #-}

handle-interaction-points : Model → (TextDocument.t → List InteractionPoint.t) → IO Model
handle-interaction-points model f = TextEditor.active-editor >>= maybe (pure model) λ e → do
  doc ← TextEditor.document e
  let ips = f doc
  just (mkFile old-ips _) ← pure (model .loaded-files !? TextDocument.file-name doc) where _ → pure model

  -- Agda can respond with 0-wide interaction points in give and refinement interactioans, but we cannot extract
  -- any useful information from them (e.g. they have non-sensical and overlapping positions). Therefore, we just
  -- ignore them and reload the file afterwards to get more relevant information about new goals.
  let ips = ips
        |> filter (not ∘ Range.empty? ∘ range)
  
  -- After a refinement, Agda may send 1-wide interaction points at places where originally already
  -- expanded interaction points were. We try to merge the 1-wide goals with the previous goals to
  -- make sure that the previous goals will not be broken by new hole digs introduced by these faultily-sized
  -- goals.
        |> map (merge-ip old-ips)

  -- Dig the remaining 1-wide goals, this involves updating the goal cache in the model as well as
  -- performing edits in the buffer. In case of multiple digs, the edits send the current positions
  -- of the question marks and vscode shifts them internally. Whereas the goal cache requires that
  -- newly dug holes are shifted to their correct position after the edits are performed. This is because
  -- the change event handler will not shift edits to goals that fall exactly onto goals according to the cache,
  -- while still shifting the tokens and goals that are not recently dug in the regular fashion.
  let expanded-ips = ips |> foldl ([] , 0) expand-interaction-point |> Σ.fst
  let edits = ips |> map-Maybe λ ip → if single-character-range? (ip .range)
        then just (Edit.replace (ip .range) "{!  !}")
        else nothing

  TextEditor.edit edits e
  TextDocument.save doc
  doc ← TextEditor.document e

  -- If a new hole has been bug, place the cursor in the middle of the first new goal
  ips |> find (single-character-range? ∘ range) |> maybe (pure tt) λ ip →
    let pos = Position.right 3 $ Range.start (ip .range) in
    TextEditor.set-selections [ Selection.new pos pos ] e

  model .loaded-files !? TextDocument.file-name doc
    |> (λ where
      (just file) → record file { interaction-points = expanded-ips }
      nothing → mkFile expanded-ips [])
    |> model .loaded-files [ TextDocument.file-name doc ]:=_
    |> (λ files → record model { loaded-files = files })
    |> pure

interaction-points-decoder : Decoder (TextDocument.t → List InteractionPoint.t)
interaction-points-decoder = do
  "InteractionPoints" ← required "kind" string where _ → ⊘
  ip-factories ← required "interactionPoints" $ list InteractionPoint.decoder
  pure λ doc → map (_$ doc) ip-factories

module GiveResult where
  data t : Set where
    parens no-parens : t
    str : String → t
open GiveResult using (parens ; no-parens ; str) public

give-result-decoder : Decoder GiveResult.t
give-result-decoder = ⦇ if required "paren" bool then succeed parens else succeed no-parens | str (required "str" string) ⦈

record GiveAction : Set where
  constructor mkGiveAction
  field
    give-result : GiveResult.t
    interaction-point : InteractionPoint.t
open GiveAction

give-action-decoder : Decoder (TextDocument.t → GiveAction)
give-action-decoder = do
  "GiveAction" ← required "kind" string where _ → ⊘
  gr ← required "giveResult" give-result-decoder
  ip-factory ← required "interactionPoint" InteractionPoint.decoder
  pure λ doc → mkGiveAction gr (ip-factory doc)

t' : Position.t → Position.t
t' p = Position.new (Position.line p + 1) (Position.char p + 1)

module ExpandState where
  data State : Set where
    in-string in-comment none : State

  _==_ : State → State → Bool
  in-string == in-string = true
  in-comment == in-comment = true
  none == none = true
  _ == _ = false

  _≠_ : State → State → Bool
  a ≠ b = not (a == b)

  record t : Set where
    constructor es
    field
      result : String
      state : State
      first-expansion : Maybe Nat
      cur-index : Nat
  open t public
open ExpandState using (es ; result ; state ; first-expansion ; cur-index ; State)

-- Split on:
-- 1. /(?<=[\s\)\}\"])--/gm, and pick the first part. The rest will be comments anyway.
-- 2. /\\*"/gm and /{-|-}/gm, then do a scan with the following algorithm
--   a. match with " and an uneven number of \ toggles string if not in comment
--   b. match with {- enables comment if not in string
--   c. match with -} disables comment if not in string
--   d. ? is expanded if not in string or in comment

single-line-comment-regex string-regex comment-start-regex comment-end-regex question-mark-regex parts-regex : String
single-line-comment-regex = "((?<=[\\s\\)\\}\"])--|^--)"
string-regex = "\\*\""
comment-start-regex = "{-"
comment-end-regex = "-}"
question-mark-regex = "(?<=[\\s\\)\\}\"])\\?|^\\?"
parts-regex =
  let regexes = string-regex ∷ comment-start-regex ∷ comment-end-regex ∷ question-mark-regex ∷ [] in
  "(" <> intercalate "|" regexes <> ")"

expand-?s : String → Maybe Nat × String
expand-?s input =
  let non-comment , other = List.uncons (split-regex input single-line-comment-regex) or-else ("" , []) in
  split-regex non-comment parts-regex
  |> foldl (es "" State.none nothing 0) (λ expand-state part →
    let semi-result = record expand-state { result = expand-state .result <> part ; cur-index = expand-state .cur-index + ∥ part ∥ˢ } in
    if part =~ string-regex ∧ (expand-state .state ExpandState.≠ State.in-comment) ∧ even? ∥ part ∥ˢ then
      record semi-result { state =
        if expand-state .state ExpandState.== State.none then State.in-string else State.none }
    else if part =~ comment-start-regex ∧ (expand-state .state ExpandState.≠ State.in-string) then
      record semi-result { state = State.in-comment }
    else if part =~ comment-end-regex ∧ (expand-state .state ExpandState.== State.in-comment) then
      record semi-result { state = State.none }
    else if part =~ question-mark-regex ∧ (expand-state .state ExpandState.== State.none) then
      record expand-state
        { result = expand-state .result <> "{!  !}"
        ; first-expansion = expand-state .first-expansion <|> just (expand-state .cur-index)
        ; cur-index = expand-state .cur-index + 6
        }
    else semi-result)
  |> λ (es result _ expansion _) → expansion , result <> join other

expand-in-ip : Range.t → TextDocument.t → Maybe Nat × String
expand-in-ip ip-range doc = TextDocument.get-text (InteractionPoint.content-range ip-range) doc |> trim |> expand-?s

handle-give-action : (AgdaInteraction.t → IO ⊤) → Model → (TextDocument.t → GiveAction) → IO Model
handle-give-action send-command model f = TextEditor.active-editor >>= maybe (pure model) λ e → do
  doc ← TextEditor.document e
  let give = f doc
  let ip-range = give .interaction-point .range
  let ip-range = Range.new (t' $ Range.start ip-range) (t' $ Range.end ip-range)
      -- TODO: Change get-text to be IO
  let content = TextDocument.get-text (InteractionPoint.content-range ip-range) doc
        |> trim
        |> expand-?s
  let expansion-index , replacement = give .give-result |> λ where
        parens → let idx , content = expand-in-ip ip-range doc in idx , "(" ++ content ++ ")"
        no-parens → expand-in-ip ip-range doc
        (str s) → expand-?s s

  let expansion-position = expansion-index <&> λ idx → Position.right (idx + 3) (Range.start ip-range)
  expansion-position |> λ where
    (just pos) → TextEditor.set-selections [ Selection.new pos pos ] e
    nothing → pure tt

  TextEditor.edit [ Edit.replace ip-range replacement ] e
  TextDocument.save doc
  model <$ send-command (iotcm doc AgdaCommand.load)

data MakeCaseVariant : Set where
  function extlam : MakeCaseVariant

make-case-variant-decoder : Decoder MakeCaseVariant
make-case-variant-decoder = string >>= λ
  { "Function" → succeed function ; "ExtendedLambda" → succeed extlam ; _ → ⊘ }

record MakeCase : Set where
  constructor mkMakeCase
  field
    clauses : List String
    ip : InteractionPoint.t
    variant : MakeCaseVariant

make-case-decoder : Decoder (TextDocument.t → MakeCase)
make-case-decoder = do
  "MakeCase" ← required "kind" string where _ → ⊘
  clauses ← required "clauses" (list string)
  ip-factory ← required "interactionPoint" InteractionPoint.decoder
  variant ← required "variant" make-case-variant-decoder
  pure λ doc → mkMakeCase clauses (ip-factory doc) variant

handle-make-case : (AgdaInteraction.t → IO ⊤) → Model → (TextDocument.t → MakeCase) → IO Model
handle-make-case send-command model f = do
  just e ← TextEditor.active-editor where _ → pure model
  doc ← TextEditor.document e
  let (mkMakeCase clauses ip variant) = f doc
  
  -- We replace the entire line the interaction point is located on. While this is not correct,
  -- we can't really do better than this. The compiler doesn't tell us where the clause is that
  -- we need to replace.
  --
  -- NOTE: This bug also exists in the emacs-mode.
  --   before        after
  -- ```agda     | ```agda
  -- f =         | f =
  --   {!  !}    |   f x = ?
  -- ```         | ```
  let ip-range = Range.new (t' $ Range.start (ip .range)) (t' $ Range.end (ip .range))
  let pos = Range.start ip-range
  let line = TextDocument.line-at doc (Position.line pos)
  
  -- Save the indentation of the line we are replacing, so that we can restore it later.
  let indentation = primStringFromList $ take-while primIsSpace (primStringToList $ TextLine.text line)

  let expansion-index , replacement = clauses
        |> map (indentation ++_)
        |> intercalate "\n"
        |> expand-?s

  TextEditor.edit [ Edit.replace (TextLine.range line) replacement ] e 
  TextDocument.save doc
  
  expansion-index |> λ where
    (just idx) → do
      doc ← TextEditor.document e
      let offset = TextDocument.offset-at doc (Position.new (Position.line pos) 0) + idx + 3
      let pos = TextDocument.position-at doc offset
      TextEditor.set-selections [ Selection.new pos pos ] e
    nothing → pure tt
  
  -- We need to issue a reload, because Agda sends the old interaction point alongside this message.
  -- Even though, we need the interaction points message for the newly inserted interaction points.
  model <$ send-command (iotcm doc AgdaCommand.load)