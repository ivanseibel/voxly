# Voxly — handoff de retomada

Atualizado em 2026-07-12.

## Estado atual

Voxly MVP macOS funciona para ditado local:

- Atalho global: segurar Command direito; soltar encerra captura.
- Microfone e Acessibilidade foram liberados no macOS.
- Whisper transcreve português/inglês; modo Automático envia `-l auto`.
- Texto é inserido por clipboard/paste no cursor atual; cursor permanece após trecho inserido.
- Histórico local, diagnóstico e cápsula de estados existem.
- Áudio temporário é removido após processamento.
- Performance: sucesso confirmado. Binários atuais são `arm64` com Metal no Apple M4.
- Modelos permanecem carregados em servidores locais durante a sessão.

## O que foi feito

- Criado pacote Swift executável macOS com SwiftUI/AppKit.
- Criadas janela principal, menubar, cápsula flutuante, modos, histórico e diagnóstico.
- Implementados captura AVAudioEngine, WAV temporário, cancelamento por Escape e descarte do áudio.
- Integrado Whisper local e fallback CLI.
- Corrigida captura de logs Whisper: stderr não entra no texto transcrito.
- Corrigido idioma Automático: Whisper recebe explicitamente `-l auto`.
- Corrigida inserção: paste no cursor evita incorporar placeholder e deixa cursor ao fim.
- Adicionados estados visíveis `Gravando`, `Transcrevendo`, `Ajustando`, `Inserido`, `Copiado` e erro.
- Criado app bundle assinado; depois criada identidade estável `Voxly Local Development` para TCC/Acessibilidade.
- Instalado Homebrew `whisper-cpp`, depois substituído por build nativo arm64/Metal.
- Instalado `llama.cpp`; modelo Qwen2.5 0.5B Instruct Q4_K_M instalado e validado.
- Criados builds nativos arm64/Metal de `whisper-cli`, `whisper-server`, `llama-cli` e `llama-server`.
- Criados servidores persistentes locais em `ModelServers.swift`.
- Trocado endpoint de refinamento de `/v1/chat/completions` para `/completion` com template Qwen.
- Adicionado feedback de duração no status final (`processamento Xs`, `Whisper Ys`).

## Bugs pendentes (ordenados por prioridade)

> BUG-1 e BUG-2 foram resolvidos — ver seção "Resolvidos" abaixo.

### BUG-3: Restauração do modo ativo entre sessões não testada/validada

**Arquivo:** `Stores.swift` linhas 17-21, `Models.swift` linha 28  
**Sintoma:** Possível perda do modo selecionado ao reabrir Voxly.  
**Causa:** Se a decodificação dos modos salvos falha (dados corrompidos, migração), `DictationMode.defaults` gera novos UUIDs. O `activeModeID` salvo em UserDefaults não encontra correspondência nos novos UUIDs e cai no primeiro modo. Lógica está correta no caminho feliz, mas não resiliente a falhas de decodificação.  
**Correção:** Validar teste de aceitação: selecionar `Limpar texto`, fechar Voxly completamente, abrir e confirmar que o modo persiste. Se falhar, investigar dados de UserDefaults.

### BUG-4: Quebras de linha artificiais no texto inserido

**Sintoma:** Captura de tela mostrou linhas quebradas no meio de palavras (`selec` / `cionar`).  
**Possíveis causas (a investigar):**
- Newline inserido pelo modelo Whisper na transcrição.
- Newline adicionado pelo modelo Llama na limpeza.
- Quebra visual do campo/balão por largura disponível (não é bug).
**Teste:** Comparar `rawText` e `finalText` no Histórico, inspecionar `\n` em cada um. Colar em campo largo/plain text. Critério: frases comuns não devem receber newline no meio de palavra.

## Melhorias pendentes

### Cápsula flutuante com posição fixa na tela

**Atual:** A cápsula de status (Gravando, Transcrevendo, Inserido, etc.) aparece próximo ao cursor do mouse.  
**Desejado:** Posição fixa: horizontalmente centralizada na tela e próximo à parte inferior (com margem confortável, não colada na borda).

## Arquitetura atual

- SwiftUI/AppKit em `Sources/VoxlyApp/`.
- `DictationCoordinator.swift`: captura, fluxo e estados.
- `Services.swift`: áudio, inserção, fallback CLI, engines locais.
- `ModelServers.swift`: servidores persistentes e HTTP local.
- `ContentView.swift`: Modos, Histórico, Diagnóstico.
- `VoxlyApp.swift`: menubar, janela e cápsula flutuante.
- `Stores.swift` / `Models.swift`: persistência local e modelos de dados.

Servidores ativos na sessão:

- Whisper: `127.0.0.1:18080/inference`
- Llama: `127.0.0.1:18081/completion`

Fontes nativas compiladas:

- `native/whisper.cpp/`
- `native/llama.cpp/`

Symlinks usados pelo app:

```text
~/Library/Application Support/Voxly/Models/whisper-cli
~/Library/Application Support/Voxly/Models/whisper-server
~/Library/Application Support/Voxly/Models/llama-cli
~/Library/Application Support/Voxly/Models/llama-server
~/Library/Application Support/Voxly/Models/ggml-small.bin
~/Library/Application Support/Voxly/Models/instruct.gguf
```

Modelo instruct atual: Qwen2.5 0.5B Instruct Q4_K_M. O Qwen 3B baixado via `curl` veio incompleto/corrompido; foi removido. 0.5B foi baixado com `aria2` e validado pelo SHA-256 publicado no repositório.

## Performance medida

- Whisper Homebrew x86/CPU: cerca de 6,9 s para áudio de 11 s.
- Whisper nativo arm64/Metal: cerca de 0,90 s para o mesmo áudio após aquecimento.
- Llama CPU: cerca de 8 tokens/s.
- Llama arm64/Metal: cerca de 100 tokens/s.
- Servidores persistentes: chamadas diretas medidas em aproximadamente 0,38 s (Whisper) e 0,31 s (Llama).
- Primeiro uso pode ser mais lento por carregamento/compilação Metal.

## Comandos de retomada

Abrir app:

```sh
open /Users/ivanseibel/dev/personal/voxly/build/Voxly.app
```

Verificar servidores:

```sh
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18081/health
```

Recompilar e empacotar:

```sh
zsh scripts/package-app.sh
```

`package-app.sh` usa assinatura estável `Voxly Local Development`. Não voltar para assinatura ad-hoc: ela fazia Acessibilidade desaparecer a cada build.

## Próximo passo recomendado

1. **BUG-3 (validação):** Testar persistência do modo ativo entre sessões.
2. **BUG-4 (investigação):** Diagnosticar origem de quebras de linha artificiais.
3. **Melhoria:** Posição fixa da cápsula flutuante.

## Resolvidos

### ✅ BUG-2: `TextInserter.insert` sempre retornava `.copied`

**Correção:** `Services.swift` — método agora retorna `.inserted` quando CGEvents são criados com sucesso, `.copied` apenas como fallback.

### ✅ BUG-1: Refinamento retornava texto sem limpeza

**Causa real:** Modelo Qwen 0.5B incapaz de edição textual em português (devolvia input idêntico). System prompt em inglês agravava.  
**Correções aplicadas:**
1. Modelo atualizado para **Llama 3.2 3B Instruct Q4_K_M** (~2 GB). O arquivo foi definido como `instruct.gguf` (symlink).
2. O formato de requisição no `LocalModelHTTP` (`ModelServers.swift`) foi corrigido para usar a rota universal compatível com a OpenAI (`/v1/chat/completions`), prevenindo problemas de tags de formatação incompatíveis entre famílias de modelos (Qwen vs Llama).
3. System prompt reescrito de forma extremamente estrita para inibir a "tagarelice" natural dos modelos ("Aqui está o resumo..."), forçando saída crua e adicionando exemplos concretos de redundância.
4. Adicionado `VoxlyLog` — logger local (`~/Library/Application Support/Voxly/voxly.log`) para monitorar as inferências.
