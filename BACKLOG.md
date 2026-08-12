# Voxly — backlog

Updated on 2026-08-12.

## Tasks

### BUG (capture fixed, UX pending): mic Bluetooth não captura com headset como default output — "Local engine returned no text"

#### Narrativa completa do problema

**Contexto — o fluxo que deveria funcionar.** O usuário pediu que o Voxly, durante a gravação, baixasse temporariamente o volume do áudio que está tocando (música no Chrome, por exemplo) para não distrair, e restaurasse depois. Isso foi implementado no commit `59bea4e` ("stabilize background audio for Bluetooth capture and duck volume"), que trouxe duas novidades: o duck de volume (`OutputVolume` em `Services.swift`) e o alinhamento de sample rate (`AudioDeviceRate.alignInputToOutput()`), cujo objetivo era impedir que o engine de captura renegociasse o clock do device e "entortasse" o tom do áudio já tocando.

**O que aconteceu.** Após instalar o build novo (2026-08-12 ~15:43), toda ditada terminava com "Local engine returned no text" no final. O usuário notou também que a música no Chrome "dá umas falhadas quando volta depois de gravar".

**Sequência de fatos observada (log `~/Library/Application Support/Voxly/voxly.log`):**
- 15:41–15:42 — build ANTIGO (antes do commit `59bea4e`): captura funcionou (54 buffers, 41 buffers, 132 buffers), formato do input lido como **16 kHz**.
- 15:44 em diante — build NOVO instalado: `Recorder finished — 0 buffers, 0 frames` em todas as tentativas. Formato do input lido como **44100 Hz**. O WAV resultante tem 4096 bytes (só o header, nenhum dado de áudio).
- 15:44:17 e 15:45:59 — `Could not pin input device sample rate to 44100.0 Hz` (tentativa do novo código de alinhar o input ao output).
- 15:44–15:46 — `HTTP error during transcription: processFailed("Whisper server unavailable")` e `whisper-cli CLI also returned empty` — consequências, não causas: o Whisper (server e CLI) recebeu um arquivo vazio e não tinha nada para transcrever. O server em si respondia `/health` com 200.
- 15:49 — build com o skip de pin para Bluetooth: `Skipping sample rate pin — Bluetooth input device (HFP) can't switch to 44100.0 Hz`, mas **ainda** `0 buffers` e formato **44100 Hz**.

**Estado do hardware (relevante):** headset **OpenComm2 by Shokz_II** (Bluetooth) configurado como default input E default output. No CoreAudio aparecem como DOIS device IDs distintos do mesmo aparelho: input id 106 (transporte HFP, nominal **16 kHz**) e output id 100 (transporte A2DP, nominal **44.1 kHz**). Demais devices: MacBook Speakers (48 kHz), MacBook Mic (44.1 kHz), iPhone Mic (48 kHz), virtual devices Immersed e Apowersoft (48/44.1 kHz).

#### Investigação empírica (binários em `/var/folders/r_/xrvhskhx45l6n66k99kzs61r0000gn/T/opencode/audiotest/`)

Programas de teste compilados com `swiftc`, capturando 4 segundos do mic e contando buffers:

- **Teste A — output = OpenComm2 (44.1 kHz):** `engine.inputNode.outputFormat(forBus: 0)` retorna **44100 Hz, 1 ch** (apesar de o device de input reportar nominal 16000 Hz via CoreAudio). `engine.start()` tem sucesso, mas o tap entrega **0 buffers em 4 s**.
- **Teste B — output = MacBook Speakers (48 kHz):** engine lê input como **48000 Hz**, entrega **40 buffers em 4 s** (captura funciona; o engine faz SRC do 16 kHz real do mic para 48 kHz).
- **Teste C — `AVCaptureSession` com `AVCaptureAudioDataOutput` no mic OpenComm2, output = headset:** sessão roda mas entrega **0 buffers**.
- **Teste D — tap com formato explícito 16 kHz, output = headset:** exceção fatal `Failed to create tap due to format mismatch` — o engine não aceita o formato do tap diferente do formato que ele próprio escolheu (44100).
- Teste A repetido depois de devolver o default output ao OpenComm2: 0 buffers de novo (reproduzível).

#### Conclusão (causa raiz)

O AVAudioEngine **harmoniza o formato do nó de entrada para o sample rate do default output** (o clock do device que toca). Quando o default output é o próprio headset Bluetooth (A2DP a 44.1 kHz), o engine instala o tap de captura a 44.1 kHz — mas o transporte HFP do mic só opera a 16 kHz e não entrega nenhum áudio nesse rate. Resultado: 0 buffers, WAV vazio, Whisper sem texto, e o fluxo de erro "Local engine returned no text" (na verdade o erro original é `VoxlyError.emptyResult`, após o CLI fallback também falhar).

O commit `59bea4e` NÃO é a causa do problema: o `alignInputToOutput` apenas logava "Could not pin" (o HFP não aceita ser pinado em 44.1 kHz) e o engine já fazia a harmonização 16→44.1 kHz sozinho, com ou sem o pin. A harmonia só não aparecia antes porque, sem stream A2DP ativo, o headset operava em HFP puro (16 kHz) e o engine lia 16 kHz — caso em que tudo funcionava (log das 15:41). O problema se manifesta quando música toca (A2DP ativo a 44.1 kHz).

**A "falhada" na música do Chrome quando o volume volta:** o headset BT tem UM clock compartilhado; ao iniciar/parar a captura o engine negocia o clock do device, o stream A2DP é perturbado e a música dá solavancos ao restaurar o volume. É sintoma da mesma limitação: o headset não sustenta mic HFP (16 kHz) e saída A2DP (44.1 kHz) simultaneamente com qualidade.

**Resumo em uma linha:** não é possível capturar o mic do OpenComm2 (HFP) enquanto o mesmo headset é o default output (A2DP 44.1 kHz) — nem com AVAudioEngine nem com AVCaptureSession; o engine só captura quando o output é outro device (comprovado pelo Teste B).

#### Já tentado (não resolveu)

1. **Skip de pin de sample rate para input Bluetooth + restore defensivo da taxa após pin falho** em `Services.swift` (`alignInputToOutput`). Aplicado e mantido (é inofensivo e corrige o log enganoso), mas não resolve: o problema é a harmonização do engine, não o pin.
2. **Tap com formato explícito de 16 kHz** — exceção format mismatch (Teste D).
3. **`AVCaptureSession`** (API alternativa de captura) — 0 buffers (Teste C).
4. **Troca temporária do default output para MacBook Speakers durante a captura** — FUNCIONA (Teste B, 40 buffers), mas não foi implementado no app: a música sairia do headset durante a gravação (talvez aceitável com o duck), e a transição de volta pode ser exatamente a "falhada" que o usuário ouve hoje.

#### Caminhos possíveis (não implementados, para o usuário avaliar)

1. Durante a gravação, trocar temporariamente o default output para outro device (ex.: MacBook Speakers) e restaurar ao final. Comprovado funcionar (Teste B). Custo: música sai do headset; risco de transição audível.
2. Usar o mic do MacBook (não-BT, 44.1 kHz nativo) como input de captura quando o output for BT. Não testado; o usuário falaria mais longe do mic do Mac.
3. Hardware: testar o OpenComm2 pelo adaptador USB ("wireless adapter"), que entrega mic e áudio em canais separados, ou outro headset BT com suporte real a multi-stream.
4. Forçar o device de input para 16 kHz via `AudioObjectSetPropertyData` imediatamente antes de `engine.start()` e verificar se o engine respeita ou re-harmoniza para 44.1 kHz (não testado; comportamento provável: re-harmoniza, como o Teste D sugere).

**Diagnóstico/ferramentas:** binários em `/var/folders/r_/xrvhskhx45l6n66k99kzs61r0000gn/T/opencode/audiotest/` — `test` (engine + tap nil), `test16k` (tap 16 kHz, crash), `capture` (AVCaptureSession), `switchout`/`switchout2` (mudam o default output do sistema! rodar devolve o output ao OpenComm2).

#### Resolução implementada

Troca temporária do default output device do sistema para um device não-Bluetooth durante a gravação (Caminho 1 do backlog). O `AudioDeviceRate.switchOutputIfNeeded()` detecta quando input e output são ambos Bluetooth, enumera os devices disponíveis, seleciona o primeiro non-BT com canais de output, e devolve uma closure de restauração. A restauração acontece em `stopAndRemove()` após liberar o engine. Safety net via `NSApplication.willTerminateNotification` garante restauração mesmo em crash.

**Refinamento (ordering + estabilização):** o duck de volume acontece ANTES da troca de output (fade suave no headset); o output volta ao BT com o volume ainda abaixado (travadas da renegociação A2DP praticamente inaudíveis); o volume só é restaurado após `outputStabilizeDelaySeconds` (configurável, default 1.5s) em `config.json`, com um retry adicional de 1s para cobrir variação de reconexão A2DP. Volume por-device: após a troca de output, o device fallback (ex.: MacBook Speakers) é silenciado com `OutputVolume.mute()` — o volume do headset e do fallback são independentes. Safety net estendida com `pendingVolumeRestore` para restaurar volume em caso de quit. Caminho futuro avaliado mas não implementado: HAL AudioUnit input-only (eliminaria a troca de output, custo: refactor do pipeline de captura).

**Refinamento (iteração 3 — estratégia simplificada):** não fazer duck no headset BT quando há troca de output — o headset não toca nada enquanto o output está em outro device, e o volume por-device do BT fica intacto, restaurando automaticamente ao voltar. Para o fallback, `OutputVolume.muteWithRestore()` salva o volume do device, muta, e restaura ANTES de voltar o output ao BT (sem delays/retries). Caso não-BT (sem troca) mantém o duck normal com restore imediato. `outputStabilizeDelaySeconds` permanece no config (inofensivo, útil no futuro).

**Refinamento (iteração 5 — save/restore BT volume):** salva o volume do BT headset ANTES de qualquer mudança (via AppleScript, enquanto BT é default output), e re-aplica após `outputStabilizeDelaySeconds` (2.5s) quando o A2DP re-estabelece. Delay de 300ms entre switch de device e leitura de volume (race condition CoreAudio async vs AppleScript). Volume restaura corretamente, MAS a transição de perfil BT (HFP→A2DP) causa artefatos audíveis por ~3-5s (som mono de baixa qualidade → corte → estéreo de alta qualidade com falhadas).

#### Problema UX do mecanismo de troca de output (HISTÓRICO — abordagem rejeitada e substituída)

A troca do `kAudioHardwarePropertyDefaultOutputDevice` do sistema é **fundamentalmente invasiva**: força transição de perfil Bluetooth (A2DP↔HFP) em TODOS os ciclos de gravação. Não importa quanto polish (delays, retries, volume saves), a transição BT sempre será audível. O usuário quer experiência tipo WhatsApp: áudio desaparece silenciosamente → gravação → áudio volta integralmente sem artefatos. **Resolvido pela implementação final abaixo (mute total + IOProc), que não troca nenhum default device.**

#### Caminhos avaliados e REJEITADOS (substituídos pela implementação final)

1. **AVAudioSession (macOS):** categoria `.playAndRecord` com `.duckOthers`/`.allowBluetooth` — não aplicável como solução: AVAudioSession é API iOS; no macOS a captura BT com AVAudioEngine falha (0 buffers — Teste A) e o duck parcial não esconde a transição de perfil.
2. **HAL AudioUnit input-only:** testado empiricamente (probes externos) — `AudioUnitRender` retorna -50 em todas as variantes e devices; não captura nada neste ambiente. **REJEITADO por evidência.**
3. **Troca temporária do default output:** implementada (iterações 1-5) e depois removida — invasiva, artefatos audíveis. **REJEITADO por decisão de produto.**

**Handoff completo:** sessão `b6cb721e`, walkthrough em `~/.gemini/antigravity-ide/brain/b6cb721e-fd75-4655-9b64-638d218cc641/walkthrough.md`.
#### Implementação final (2026-08-12) — mute total + IOProc BT, sem troca de output

Decisão de produto: **nunca trocar default input/output** — o usuário preserva o routing que escolheu. A transição A2DP↔HFP é escondida com mute total + fades, e o mic BT é capturado via IOProc direto no device (comprovado em experimentos externos: fala real transcrita a 16 kHz, classificação manual A).

Implementado:
- `RecordingOutputSilencer` (novo): snapshot de output ID/rate baseline/volume/mute; aplica `output muted` e CONFIRMA antes da captura; fade-down em paralelo (osascript único, ~400-600ms, reaplica mute a cada passo — passos de volume derrubam a flag em BT); listeners CoreAudio (`NominalSampleRate` global, `Mute` scope output, `DeviceIsRunningSomewhere`) em serial queue; watchdog 10ms→50ms como fallback; restauração BT espera retorno ao rate baseline A2DP + confirmação de 100ms (timeout `a2dpRestoreTimeoutSeconds`, default 15s — mantém mudo no timeout); não-BT restaura imediatamente. Se o usuário já estava mutado, permanece mutado.
- `IOProcBackend` (novo): `AudioDeviceCreateIOProcID`+`AudioDeviceStart` no input BT, WAV 16-bit válido com header fechado no stop, suporta Float32/Int16 interleaved e non-interleaved, level meter seguro, logs de callbacks/frames/bytes/duração. Falha de start → erro claro, sem fallback para AVAudioEngine em BT.
- `AVEngineBackend` (novo): AVAudioEngine preservado para inputs não-BT, iniciado após mute confirmado (sem esperar fade), restore imediato no stop.
- Removido legado: `switchOutputIfNeeded`, `alignInputToOutput`, `pendingOutputRestore`, `restoreOutput`, `restoreFallbackVolume`, `savedBTVolume`, `OutputVolume.duck`, `outputStabilizeDelaySeconds`, `duckVolumeFactor`. `applicationWillTerminate` restaura apenas o estado de silenciamento pendente.
- Config: `a2dpRestoreTimeoutSeconds` (default 15.0) substitui `outputStabilizeDelaySeconds`.
- Corretiva (revisão): `applicationWillTerminate` agora para a captura ANTES de restaurar volume; se o output BT estiver fora do baseline A2DP ao encerrar, o mute é mantido (nunca expõe HFP em volume normal) — o usuário desmuta pelo menu de som ou relançando o app. Troca de default output durante a gravação: **abandono seguro** — nenhum volume/mute é escrito no output novo, o snapshot do device antigo nunca é aplicado a outro device, o output anterior pode permanecer como estava no instante da troca; loga IDs antigo/novo e limpa IOProc/listeners/watchdog/estado ocupado normalmente (`abandonRestoreAfterOutputChange`). `forceRestore` é idempotente e seguro em meio à captura (libera watchdog/listeners antes de decidir).

Validação: `swift build` OK; `zsh scripts/package-app.sh` OK (codesign preservado); `git diff --check` limpo; `swift test` bloqueado por ambiente (`no such module 'XCTest'` — SDK CommandLineTools sem XCTest; não alterado Package.swift).

Testes manuais pendentes: headset BT input+output com música; BT input/não-BT output; input interno/USB; cancelar durante captura; encerrar app durante captura; usuário já mutado antes de gravar.
