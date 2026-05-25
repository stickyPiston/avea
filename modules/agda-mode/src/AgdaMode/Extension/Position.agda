module AgdaMode.Extension.Position where

open import Data.Nat
import Data.Nat as Nat
open import Data.Int hiding (_+_) ; import Data.Int as Int
open import Data.Bool
open import Class.Ord
open import Class.Monoid
open import Data.Maybe ; open import Data.Maybe.Effectful
open import Data.String hiding (∥_∥ ; _==_)
open import Data.Product
import Data.String as String
open import Data.List hiding (_++_) ; import Data.List as List
open import Data.Map
open import Function
open import Data.IO
open import Effect.Monad
open Monad {{ ... }}
open import Agda.Builtin.Unit

open import AgdaMode.Extension.ProcessQueue
open import AgdaMode.Extension.Model
open import AgdaMode.Extension.Highlighting.Decode

open import Class.Show

open import Vscode.TextEditor
open import Vscode.Common

module Change where
  record t : Set where
    constructor mkChange
    field
      source-range : Range.t
      end-pos : Position.t
  open t public

  start-line : t → Nat
  start-line (mkChange src _) = Position.line $ Range.start src

  replacement-range : TextDocument.t → t → Range.t
  replacement-range doc change =
    Range.new (Range.start $ change .source-range) (change .end-pos)

  -- TODO: Because min and max each form a Semigroup for any Set A, Changes with combine also forms a Semigroup. 
  combine : t → t → t
  combine c₁@(mkChange src₁ end₁) c₂@(mkChange src₂ end₂) =
    let start c = Range.start (c .source-range) in
    let source c = Range.end (c .source-range) in
    let target c = c .end-pos in 
    mkChange (Range.new (min (start c₁) (start c₂)) (max (source c₁) (source c₂))) (max (target c₁) (target c₂))

  influences? : Range.t → t → Bool
  influences? range (mkChange source-range single-line-replacements) =
    from-Maybe false (not ∘ Range.empty? <$> range Range.∩ source-range)

  open TextDocumentContentChangeEvent hiding (t)

  from-TextDocumentContentChangeEvent : TextDocumentContentChangeEvent.t → t
  from-TextDocumentContentChangeEvent change =
    let lines = String.split (change .text) "\n" in
    lines |> λ where
      [] → mkChange (change .range) (Range.start $ change .range)
      [ line ] → mkChange (change .range) (Position.right String.∥ line ∥ $ Range.start (change .range))
      (_ ∷ line ∷ lines) →
        let last-line = last lines or-else line in
        let start-pos = Range.start $ change .range in
        mkChange (change .range) (Position.new (Position.line start-pos + ∥ line ∷ lines ∥) String.∥ last-line ∥)
open Change using (mkChange ; source-range ; end-pos) public

instance
  Show-Change : Show Change.t
  Show-Change = record
    { show = λ where
      (mkChange src-rng end-pos) → intercalate " " ("mkChange" ∷ show src-rng ∷ show end-pos ∷ [])
    }

  Ord-Change : Ord Change.t
  Ord-Change = record
    { compare =
      let start-pos (mkChange src _) = (Position.line (Range.start src) , Position.char (Range.start src)) in
      compare on start-pos
    }

_n+i_ : Nat → Int → Nat
n n+i pos m = n + m
n n+i negsuc m = n - suc m

shift-pos : Change.t → Position.t → Position.t
shift-pos (mkChange src-rng end-pos) p =
  if p < Range.start src-rng then
    p
  else
    let Δy = Position.line end-pos ⊝ Position.line (Range.end src-rng) in
    if Position.line (Range.end src-rng) == Position.line p then
      Position.new
        (Position.line p n+i Δy)
        (Position.char end-pos + (Position.char p - Position.char (Range.end src-rng)))
    else
      Position.new (Position.line p n+i Δy) (Position.char p)

shift-range : Change.t → Range.t → Range.t
shift-range c r = Range.new (shift-pos c $ Range.start r) (shift-pos c $ Range.end r)

shift-change : Change.t → Change.t → Change.t
shift-change by (mkChange src tgt) =
  mkChange (shift-range by src) (shift-pos by tgt)

shift-changes : List Change.t → List Change.t
shift-changes changes =
  -- NOTE: We need to create origin inside of the function, because AgdaModeImports
  -- only exists at runtime of the extension, and NOT at import time. This can be fixed
  -- once FOREIGN JS is released.
  let origin = Position.new 0 0 in
  let empty-change = mkChange (Range.new origin origin) origin in
  changes
    |> (foldl (empty-change , []) λ (acc , res) change →
      let transformed-change = shift-change acc change in
      Change.combine acc transformed-change , res <> [ transformed-change ])
    |> Σ.snd

handle-offset-change : Change.t → Range.t → Maybe Range.t
handle-offset-change c r =
  if Position.before? (Range.end r) (Range.start $ c .source-range) then just r
  else if Change.influences? r c then nothing
  else
    let shifted-start-pos = shift-pos c $ Range.start r in
    just (Range.new shifted-start-pos $ Position.right (Range.length r) shifted-start-pos)

handle-tokens-change : List Token.t → Change.t → List Token.t
handle-tokens-change tokens change = tokens |> map-Maybe λ token →
  token .range
  |> handle-offset-change change
  |> fmap λ range → record token { range = range }

handle-ips-change : TextDocument.t → List InteractionPoint.t → Change.t → List InteractionPoint.t
handle-ips-change doc ips change = ips |> map-Maybe λ ip@(mkInteractionPoint id ip-range) →
  if Range.equals? (Change.replacement-range doc change) ip-range then
    pure ip
  else do
    start-marker ← InteractionPoint.start-marker ip |> handle-offset-change change
    end-marker ← InteractionPoint.end-marker ip |> handle-offset-change change
    pure $ mkInteractionPoint id (start-marker Range.∪ end-marker)

private
  postulate trace : {A : Set} → A → IO ⊤
  {-# COMPILE JS trace = A => a => async () => { console.log(a); return b => b["tt"]() } #-}

register-change-handler : AgdaProcess.t → Ref.t Model → IO ⊤
register-change-handler agda model-ref =
  Workspace.on-did-change-text-document λ e → e .content-changes |> λ where
    -- Vscode sends change events with no content changes, we are not interested in those, so we ignore them.
    [] → pure tt
    _ → agda .response-queue |> JobQueue.await-push (do
      model ← Ref.get model-ref
      let doc = e .document
      model .loaded-files !? TextDocument.file-name doc |> λ where
        (just (mkFile ips tokens)) → do
          -- The changes this handler receives are not yet sorted and shifted, so we need to do that ourselves
          -- to be able to compare changes to exisiting interaction points locations.
          let changes = e .content-changes
                |> map Change.from-TextDocumentContentChangeEvent
                |> sort-Ord
                |> shift-changes
          
          let new-tokens = changes |> foldl tokens handle-tokens-change

          -- If one of the changes involved the insertion of a newly dug goal, then we need to do some extra work,
          -- Otherwise, we take a shortcut to keep the processing time on each edit minimal.
          let new-ips =
                if List.any (λ change → change .text String.== "{!  !}") (e .content-changes) then (
                  -- We partition the list of interaction points into
                  -- * a list of ips that have been dug in these changes, i.e. changes that fall exactly over an
                  --   interaction point in the cache;
                  -- * a list of ips that need to be shifted as regular.
                  let exactly-on-change? ip = List.any (Range.equals? (ip .range) ∘ Change.replacement-range doc) changes in
                  let newly-dug-ips , old-ips = partition exactly-on-change? ips in
                  changes |> foldl old-ips (handle-ips-change doc) |> append newly-dug-ips
                ) else (changes |> foldl ips (handle-ips-change doc))

          Ref.set model-ref record model
            { loaded-files = model .loaded-files [ TextDocument.file-name doc ]:= mkFile new-ips new-tokens }
        nothing → pure tt
      EventEmitter.fire (model .tokens-request-emitter) tt)