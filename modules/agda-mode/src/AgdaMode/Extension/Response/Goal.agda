module AgdaMode.Extension.Response.Goal where

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

-- TODO: The order of the interaction point list does not matter, so we might as well cons the ips instead of
-- inefficiently snoc'ing them.
expand-interaction-point : List InteractionPoint.t × Nat → InteractionPoint.t → List InteractionPoint.t × Nat
expand-interaction-point (ac , Δ) ip =
  if ip .range .length > 1 then
    ac List.++ [ ip ] , Δ
  else
    ac List.++ [ record ip { range = record (ip .range) { start = ip .range .start + Δ ; length = 6 } } ] , Δ + 5

-- This function only merges 1-wide interaction points with old interactions points. It should not occur that
-- interaction overlap in any other way.
merge-ip : List InteractionPoint.t → InteractionPoint.t → InteractionPoint.t
merge-ip old-ips ip =
  let old-ip = find (λ expanded-ip → OffsetRange.contains? (expanded-ip .range) (ip .range .start)) old-ips in
  (ip .range .length , old-ip) |> λ where
    (1 , just old-ip) → old-ip
    (_ , _) → ip

handle-interaction-points : Model → List InteractionPoint.t → IO Model
handle-interaction-points model ips = TextEditor.active-editor >>= maybe (pure model) λ e → do
  doc ← TextEditor.document e
  just (mkFile old-ips _) ← pure (model .loaded-files !? TextDocument.file-name doc) where _ → pure model

  -- Agda can respond with 0-wide interaction points in give and refinement interactioans, but we cannot extract
  -- any useful information from them (e.g. they have non-sensical and overlapping positions). Therefore, we just
  -- ignore them and reload the file afterwards to get more relevant information about new goals.
  let ips = ips
        |> filter (λ ip → ip .range .length > 0)
  
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
  let edits = ips |> map-Maybe λ ip → if ip .range .length ≤ 1
        then just (Edit.replace (OffsetRange.to-vsc-range doc (ip .range)) "{!  !}")
        else nothing

  TextEditor.edit edits e
  TextDocument.save doc
  doc ← TextEditor.document e

  -- If a new hole has been bug, place the cursor in the middle of the first new goal
  ips |> find (λ ip → ip .range .length ≤ 1) |> maybe (pure tt) λ ip →
    let pos = TextDocument.position-at doc (ip .range .start + 3) in
    TextEditor.set-selections [ Selection.new pos pos ] e

  model .loaded-files !? TextDocument.file-name doc
    |> (λ where
      (just file) → record file { interaction-points = expanded-ips }
      nothing → mkFile expanded-ips [])
    |> model .loaded-files [ TextDocument.file-name doc ]:=_
    |> (λ files → record model { loaded-files = files })
    |> pure

interaction-points-decoder : Decoder (List InteractionPoint.t)
interaction-points-decoder = do
  "InteractionPoints" ← required "kind" string where _ → ⊘
  required "interactionPoints" $ list InteractionPoint.decoder

module GiveResult where
  data t : Set where
    parens no-parens : t
    str : String → t

  show : t → String
  show (str s) = s
  show _ = ""
open GiveResult using (parens ; no-parens ; str) public

give-result-decoder : Decoder GiveResult.t
give-result-decoder = ⦇ if required "paren" bool then succeed parens else succeed no-parens | str (required "str" string) ⦈

record GiveAction : Set where
  constructor mkGiveAction
  field
    give-result : GiveResult.t
    interaction-point : InteractionPoint.t
open GiveAction

give-action-decoder : Decoder GiveAction
give-action-decoder = do
  "GiveAction" ← required "kind" string where _ → ⊘
  mkGiveAction <$> required "giveResult" give-result-decoder <*> required "interactionPoint" InteractionPoint.decoder

handle-give-action : (AgdaInteraction.t → IO ⊤) → Model → GiveAction → IO Model
handle-give-action send-command model give = TextEditor.active-editor >>= maybe (pure model) λ e → do
  doc ← TextEditor.document e
  let ip-range = OffsetRange.to-vsc-range doc (give .interaction-point .range)
      -- TODO: Change get-text to be IO
  let content = trim $ TextDocument.get-text (OffsetRange.to-vsc-range doc $ InteractionPoint.content-range (give .interaction-point)) doc
  let edits = give .give-result |> λ where
        parens → [ Edit.replace ip-range ("(" ++ content ++ ")") ]
        no-parens → [ Edit.replace ip-range content ]
        (str s) → [ Edit.replace ip-range s ]
  TextEditor.edit edits e
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

make-case-decoder : Decoder MakeCase
make-case-decoder = do
  "MakeCase" ← required "kind" string where _ → ⊘
  ⦇ mkMakeCase
    (required "clauses" (list string))
    (required "interactionPoint" InteractionPoint.decoder)
    (required "variant" make-case-variant-decoder) ⦈

handle-make-case : (AgdaInteraction.t → IO ⊤) → Model → MakeCase → IO Model
handle-make-case send-command model (mkMakeCase clauses ip variant) = do
  just e ← TextEditor.active-editor where _ → pure model
  doc ← TextEditor.document e
  
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
  let pos = TextDocument.position-at doc (ip .range .start)
  let line = TextDocument.line-at doc (Position.line pos)
  
  -- Save the indentation of the line we are replacing, so that we can restore it later.
  let indentation = primStringFromList $ take-while primIsSpace (primStringToList $ TextLine.text line)

  TextEditor.edit [ Edit.replace (TextLine.range line) (intercalate "\n" $ map (indentation ++_) clauses) ] e 
  TextDocument.save doc
  
  -- We need to issue a reload because Agda sends interaction points that, for some reason,
  -- have already been expanded by the compiler. This means that the interaction points message
  -- that follows the make case message, will not expand the question marks that we have inserted
  -- here, since Agda sends 6-wide ranges instead of 1-wide at the places the questions marks are
  -- located.
  --
  -- NOTE: Fixing this would require the compiler to not expand the question marks. This would
  -- be more consistent with the interaction points messages that refine sends too.
  model <$ send-command (iotcm doc AgdaCommand.load)