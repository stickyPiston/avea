module AgdaMode.Extension.ProcessQueue where

open import Data.Bool
import Data.List as List
open List using (List ; [_] ; _∷_ ; [] ; filter)
open import Data.List.NonEmpty
open import Data.List.Queue
open import Data.IO
open import Data.Maybe
open import Data.Maybe.Effectful
open import Data.Product
open import Function
open import Agda.Builtin.Unit
open import Data.JSON
open import Data.Nat
open import Data.Map
open import Data.JSON.Decode
open import Data.String as String
open import Data.Either

open import AgdaMode.Extension.Model
open import AgdaMode.Extension.Response

open import Vscode.SemanticTokensProvider
open import Vscode.Common
open import Vscode.Window
open import Vscode.Logging
open import Vscode.Command

open import Node.Process

open import Class.Monoid
open import Class.Show
open import Class.Ord

open import Effect.Monad
open Monad {{ ... }}
open List.TraversableM {{ ... }}

-- The job queue makes sure that only one job is executed at the same time.
module JobQueue where
  postulate t : Set

  Job : Set
  Job = IO ⊤

  postulate new : IO t
  {-# COMPILE JS new = async () => { return new AgdaModeImports.PQueue({ concurrency: 1 }); } #-}

  postulate push : Job → t → IO ⊤
  {-# COMPILE JS push = job => q => async () => { q.add(job); return a => a["tt"]() } #-}

  postulate await-push : {A : Set} → IO A → t → IO A
  {-# COMPILE JS await-push = A => job => q => async () => { return await q.add(job) } #-}

  postulate start pause : t → IO ⊤
  {-# COMPILE JS start = q => async () => { q.start(); return a => a["tt"]() } #-}
  {-# COMPILE JS pause = q => async () => { q.pause(); console.log(q.isPaused); return a => a["tt"]() } #-}

  postulate paused? : t → IO Bool
  {-# COMPILE JS paused? = q => async () => { return q.isPaused } #-}

private
  postulate trace : {A : Set} → A → IO ⊤
  {-# COMPILE JS trace = A => a => async () => { console.log(a); return b => b["tt"]() } #-}

module AgdaProcess where
  open import Data.String

  record t : Set where field
    process : Ref.t Process.t
    response-queue : JobQueue.t
    send-queue : JobQueue.t
  open t public

  -- Sent interactions are first put into a queue, so that the handler can have some time to initialise
  -- before any messages are sent. This prevents the interaction-queue to be zipped with the initial JSON>
  -- message causing the interaction queue to fall behind on the actually sent interactions.
  send-command : OutputChannel.t → Ref.t Model → AgdaInteraction.t → t → IO ⊤
  send-command output-chan model-ref intr t = do
    t .send-queue |> JobQueue.push (do
      OutputChannel.trace ("Sending interaction to Agda: " ++ String.trim (show intr)) output-chan
      model-ref |> Ref.modify λ model → record model
        { interaction-queue = model .interaction-queue |> Queue.enqueue intr }
      Ref.get (t .process) >>= Process.write (show intr))

  private
    -- Some responses from the interaction mode might start with "JSON> ", so we strip
    -- those if they are present to make sure the JSON parser can parse the actual JSON.
    strip-prompt : String → String
    strip-prompt s = s |> _starts-with "JSON> " |> λ where
      true → slice 6 ∥ s ∥ s
      false → s

    -- Once we have a response string, we can parse it into JSON and run one of the many
    -- response decoders and handler on it. These will update the model mutable variable,
    -- which is safe since this handler will be executed as a job in the `JobQueue.t`.
    handle-immediate-response : OutputChannel.t → Ref.t Model → JSON → Ref.t Process.t → JobQueue.Job
    handle-immediate-response output-chan model-ref parsed-response proc-ref = do
      OutputChannel.trace ("Handling response: " <> show parsed-response) output-chan
      model ← Ref.get model-ref
      new-model ← handle-agda-message (λ intr → do
        OutputChannel.trace ("Sending interaction to Agda: " ++ String.trim (show intr)) output-chan
        Ref.get proc-ref >>= Process.write (show intr)) model-ref model parsed-response or-else pure model
      Ref.set model-ref new-model

    handle-interaction-result : OutputChannel.t → Ref.t Model → List JSON → Ref.t Process.t → JobQueue.Job
    handle-interaction-result output-chan model-ref parsed-responses proc-ref =
      tt <$ (parsed-responses |> mapM λ parsed-response →
        handle-immediate-response output-chan model-ref parsed-response proc-ref)

    spawn-proc : OutputChannel.t → IO Process.t
    spawn-proc output-chan = do
      -- We reload the config every time spawn is called, so that when the user issues a reload agda command,
      -- the possibly updated configuration from the vscode settings is also applied.
      config ← Config.load
      let args = "--interaction-json" ∷ filter (λ s → ∥ s ∥ > 0) (NE.to-List $ split (config .extra-args) " ")
      let cmd-name = config .agda-path or-else "agda"
      OutputChannel.trace ("Spawning process: " ++ cmd-name ++ " " ++ intercalate " " args) output-chan
      Process.spawn cmd-name args

    immediate-kind? : String → Bool
    immediate-kind? s =
      let kinds = "ClearHighlighting" ∷ "HighlightingInfo" ∷ "ClearRunningInfo" ∷ "RunningInfo" ∷ "Status" ∷ [] in
      List.any (String._==_ s) kinds

    parse-json-Either : String → Either String JSON
    parse-json-Either input = parse-json input |> λ where
      nothing → left ("JSON parse error: " <> input)
      (just json) → right json

    empty-string? : String → Bool
    empty-string? "" = true
    empty-string? _ = false

    -- Whenever a buffer of data is received, we append to it to previously read and unparsed data.
    -- This complete buffer is split on newlines and the "JSON >" prompts are removed. All of the
    -- full lines should be JSON strings with responses, and jobs to parse and handle them will be pushed
    -- to the job queue.
    on-data-handler : Ref.t Process.t → (res-queue send-queue : JobQueue.t) → Ref.t Model → OutputChannel.t → Ref.t String → Buffer.t → IO ⊤
    on-data-handler proc-ref res-queue send-queue model-ref output-chan stdout-buffer received-buffer = do
      model ← Ref.get model-ref
      let interaction-queue = model .interaction-queue

      buffer ← (_++ Buffer.to-string received-buffer) <$> Ref.get stdout-buffer
      let init-intrs , last-intr = split buffer "JSON> " |> NE.map lines |> NE.unsnoc

      let last-intr , new-buffer = NE.unsnoc last-intr
      Ref.set stdout-buffer new-buffer

      -- Parse all responses to JSON, while collecting all JSON parse errors to send them to the output channel
      let errors , init-intr = init-intrs
            |> List.map (List.partition-Either ∘ List.map parse-json-Either ∘ List.filter (not ∘ empty-string?) ∘ NE.to-List)
            |> List.unzip
      errors |> List.concat |> mapM λ error → OutputChannel.error error output-chan
      let lines-per-intr = NE.snoc init-intr (List.map-Maybe parse-json last-intr)
            |> λ { (x :| xs) → (model .current-interaction <> x) :| xs }

      let immediate-responses , (complete-intrs , incomplete-intr) = lines-per-intr
            |> NE.map (List.partition (from-Maybe false ∘ fmap immediate-kind? ∘ required "kind" string))
            |> NE.unzip
            |> map-first (List.concat ∘ NE.to-List)
            |> map-second NE.unsnoc

      immediate-responses |> mapM λ immediate →
        res-queue |> JobQueue.push (handle-immediate-response output-chan model-ref immediate proc-ref)

      complete-intrs
        |> List.zip interaction-queue
        |> mapM λ (intr , intr-res) → do
          OutputChannel.trace ("Completed interaction: " <> show intr) output-chan
          res-queue |> JobQueue.push (handle-interaction-result output-chan model-ref intr-res proc-ref)

      -- Agda will send an initial JSON> prompt to indicate it is ready to receive interactions,
      -- so we wait for that to be parsed, then we start the send queue.
      send-paused? ← JobQueue.paused? send-queue
      when (send-paused? ∧ not (List.null? complete-intrs)) $ do
        OutputChannel.trace "Finished initialisation of the Agda process stdout data handler" output-chan
        JobQueue.start send-queue

      Ref.set model-ref record model
        { interaction-queue = Queue.skip List.∥ complete-intrs ∥ interaction-queue
        ; current-interaction = incomplete-intr
        }
            
    {-# TERMINATING #-}
    mutual
      -- A child process calls this handler when:
      -- - The process failed to spawn or has unexpectedly exited
      -- - A message fails to send
      -- There is not much we do can other than allow the user to restart the process.
      on-error-handler : Ref.t Process.t → (res-queue send-queue : JobQueue.t) → Ref.t Model → OutputChannel.t → String → Bool → IO ⊤
      on-error-handler proc-ref res-queue send-queue model-ref output-chan msg is-ENOENT = do
        OutputChannel.error ("Agda process error: " ++ msg) output-chan

        -- When the binary could not be spawed, give a specicialsed message and an additional button in the
        -- error to let the user know the path to the Agda binary might not be correct, or the PATH is not
        -- set up correctly.
        let message = if is-ENOENT
              then "Could not spawn Agda process. Are you sure Agda has correctly been installed on your path, or is the path to the binary in the settings correct?"
              else "Agda process error: " ++ msg
        let options = if is-ENOENT then "Open settings" ∷ "Restart Agda" ∷ [] else [ "Restart Agda" ]
        
        Window.show-error-message message options >>= λ where
          (just "Restart Agda") → do
            proc ← spawn-proc output-chan
            Ref.set proc-ref proc
            setup-handlers proc-ref res-queue send-queue model-ref output-chan
          (just "Open settings") → execute-command "workbench.action.openSettings" "agda-mode.agda-path"
          _ → pure tt

      setup-handlers : Ref.t Process.t → (res-queue send-queue : JobQueue.t) → Ref.t Model → OutputChannel.t → IO ⊤
      setup-handlers proc-ref res-queue send-queue model-ref output-chan = do
        proc ← Ref.get proc-ref
        stdout-buffer ← Ref.new ""

        -- The handlers for these event listeners have been extracted because of a compilation bug in Agda.
        -- When pattern matching directly in this function, the code in the pattern match arms is not
        -- executed for some reason.
        Process.on-data proc (on-data-handler proc-ref res-queue send-queue model-ref output-chan stdout-buffer)
        Process.on-error proc (on-error-handler proc-ref res-queue send-queue model-ref output-chan)

  stop : OutputChannel.t → t → IO ⊤
  stop output-chan t = do
    OutputChannel.trace "Stopping currently running agda process" output-chan
    Ref.get (t .process) >>= Process.kill

  -- We first kill the currently running process, then spawn a new one and put it
  -- in the mutable variable. Then we set up all the handlers again.
  restart : OutputChannel.t → Ref.t Model → t → IO ⊤
  restart output-chan model-ref t = do
    -- Pause the send queue so that the new process has time to initialise before
    -- receiving new interactions from the extension. The on-data handler will start
    -- the send queue once the handler is initialised.
    JobQueue.pause (t .send-queue)
    stop output-chan t
    proc ← spawn-proc output-chan
    Ref.set (t .process) proc
    setup-handlers (t .process) (t .response-queue) (t .send-queue) model-ref output-chan

  -- Spawn a new `AgdaProcess.t` and immediately bind to the output on the stdout channel, which
  -- When messages arrive on the output channel, they will be handled via a `JobQueue.t`.
  spawn : OutputChannel.t → Ref.t Model → IO (t × Disposable.t)
  spawn output-chan model-ref = do
    proc ← spawn-proc output-chan
    proc-ref ← Ref.new proc
    res-queue ← JobQueue.new
    send-queue ← JobQueue.new ; JobQueue.pause send-queue
    setup-handlers proc-ref res-queue send-queue model-ref output-chan

    let r = record
          { process = proc-ref
          ; response-queue = res-queue
          ; send-queue = send-queue
          }
    -- The disposable for an `AgdaProcess.t` calls `Process.kill`, which kills the child process gracefully.
    -- It will also cancel the on-data event listener created earlier.
    pure $ r , Disposable.new (Process.kill proc)
open AgdaProcess using (response-queue ; process) public