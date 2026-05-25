module AgdaMode.Extension.Highlighting.Decode where

open import Data.Maybe
open import Data.Bool
open import Data.List
import Data.List as List
open import Data.Nat ; import Data.Nat as Nat
open import Data.Product
open import Data.String
import Data.String as String
open import Data.Maybe
open import Data.Maybe.Effectful
open import Data.JSON
open import Data.JSON.Decode hiding (string)
import Data.JSON.Decode as Decode
open import Function
open import Data.Int hiding (_+_)
open import Class.Show
open import Class.Monoid
open import Class.Ord

open import Vscode.Common

open import Effect.Monad
open MonadPlus {{ ... }}

_∈[_⋯_] : Nat → Nat → Nat → Bool
n ∈[ lo ⋯ hi ] = lo ≤ n ∧ n ≤ hi

module OffsetRange where
  record t : Set where
    constructor offset-range
    field
      start length : Nat
  open t public

  end : t → Nat
  end r = r .start + r .length - 1

  shift : Int → t → t
  shift (pos n) r = record r { start = r .start + n }
  shift (negsuc n) r = record r { start = r .start - suc n }

  contains? : t → Nat → Bool
  contains? r o = o ∈[ r .start ⋯ r .start + r .length ]

  equals? : t → t → Bool
  equals? (offset-range s₁ l₁) (offset-range s₂ l₂) = s₁ Nat.== s₂ ∧ l₁ Nat.== l₂

  open import Vscode.Common

  to-vsc-range : TextDocument.t → t → Range.t
  to-vsc-range doc (offset-range start length) =
    let start-pos = TextDocument.position-at doc start in
    let end-pos = TextDocument.position-at doc (start + length) in
    Range.new start-pos end-pos

open OffsetRange using (offset-range ; start ; length) public

instance
  Show-OffsetRange : Show OffsetRange.t
  Show-OffsetRange = record
    { show = λ where
      (offset-range start length) → "offset-range " <> show start <> " " <> show length
    }

module NameKind where
  data t : Set where
    bound generalisable inductive-constructor coinductive-constructor : t
    datatype field' function module' postulate' primitive' record' argument macro' : t

  private
    string-decoder : Decoder t
    string-decoder = Decode.string >>= λ where
      "bound" → succeed bound ; "generalizable" → succeed generalisable ; "inductiveconstructor" → succeed inductive-constructor
      "coinductiveconstructor" → succeed coinductive-constructor ; "datatype" → succeed datatype ; "field" → succeed field'
      "function" → succeed function ; "module" → succeed module' ; "postulate" → succeed postulate' ; "record" → succeed record'
      "argument" → succeed argument ; "macro" → succeed macro' ; _ → ⊘

  decoder : Decoder (Maybe t)
  decoder = list Decode.any <&> (asum ∘ map string-decoder)

module PrimaryAspect where
  data t : Set where
    comment keyword string number hole symbol primitive-type pragma background markup : t
    name : Maybe NameKind.t → Bool → t

  private
    string-decoder : Decoder t
    string-decoder = Decode.string >>= λ where
      "comment" → succeed comment ; "keyword" → succeed keyword ; "string" → succeed string
      "number" → succeed number ; "hole" → succeed hole ; "symbol" → succeed symbol
      "primitive" → succeed primitive-type ; "pragma" → succeed pragma 
      "background" → succeed background ; "markup" → succeed markup ; _ → ⊘

    operator-decoder : Decoder Bool
    operator-decoder = list Decode.string <&> List.any (String._== "operator")
 
  decoder : Decoder (Maybe t)
  decoder = do
    things ← list Decode.any
    succeed $ asum (map string-decoder things) <|> (| name (NameKind.decoder (j-array things)) (operator-decoder (j-array things)) |)

module SecondaryAspect where
  data t : Set where
    error error-warning dotted-pattern unsolved-meta unsolved-constraint : t
    termination-problem positivity-problem dead-code shadowing-in-telescope : t
    coverage-problem type-checks missing-definition instance-problem : t
    cosmetic-problem catchall-clause confluence-problem : t

  private
    string-decoder : Decoder t
    string-decoder = Decode.string >>= λ where
      "error" → succeed error ; "errorwarning" → succeed error-warning ; "dottedpattern" → succeed dotted-pattern
      "unsolvedmeta" → succeed unsolved-meta ; "unsolvedconstraint" → succeed unsolved-constraint
      "terminationproblem" → succeed termination-problem ; "positivityproblem" → succeed positivity-problem
      "deadcode" → succeed dead-code ; "shadowingintelescope" → succeed shadowing-in-telescope
      "coverageproblem" → succeed coverage-problem ; "typechecks" → succeed type-checks
      "missingdefinition" → succeed missing-definition ; "instanceproblem" → succeed instance-problem
      "cosmeticproblem" → succeed cosmetic-problem ; "catchallclause" → succeed catchall-clause
      "confluenceproblem" → succeed confluence-problem ; _ → ⊘

  decoder : Decoder (List t)
  decoder = list Decode.any <&> map-Maybe string-decoder  

module DefinitionSite where
  record t : Set where
    constructor mk-DefinitionSite
    field
      filepath : String
      position : Nat
  open t public

  decoder : Decoder t
  decoder = (| mk-DefinitionSite (required "filepath" Decode.string) (required "position" nat) |)
open DefinitionSite using (filepath ; position) public

range-decoder : Decoder (TextDocument.t → Range.t)
range-decoder = do
  start ← list nat |> index 0 |> fmap (_- 1)
  end ← list nat |> index 1 |> fmap (_- 1)
  pure λ doc →
    let start-pos = TextDocument.position-at doc start in
    let end-pos = TextDocument.position-at doc end in
    Range.new start-pos end-pos

module Token where
  record t : Set where
    constructor mk-Token
    field
      primary : Maybe PrimaryAspect.t
      secondary : List SecondaryAspect.t -- Officially a set
      note : String
      definition-site : Maybe DefinitionSite.t
      token-based : Bool
      range : Range.t
  open t public

  decoder : Decoder (TextDocument.t → t)
  decoder = do
    pas ← required "atoms" PrimaryAspect.decoder
    sas ← required "atoms" SecondaryAspect.decoder
    note ← required "note" Decode.string
    ds ← optional-null "definitionSite" DefinitionSite.decoder
    tb? ← required "tokenBased" Decode.string <&> ("TokenBased" String.==_)
    range-factory ← required "range" range-decoder
    pure $ λ doc → mk-Token pas sas note ds tb? (range-factory doc)
open Token using (primary ; secondary ; note ; definition-site ; token-based ; range) public

highlighting-info-decoder : Decoder (TextDocument.t → List Token.t × Bool)
highlighting-info-decoder = required "kind" Decode.string >>= λ where
  "HighlightingInfo" → do
    tokens-factory , remove? ← required "info" (| required "payload" (list Token.decoder) , required "remove" bool |)
    pure λ doc → map (_$ doc) tokens-factory , remove?
  _ → ⊘
