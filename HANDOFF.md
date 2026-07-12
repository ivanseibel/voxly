# Voxly — handoff de retomada

Atualizado em 2026-07-12.

## Estado atual

O MVP macOS funciona para ditado local:

- Segurar Command direito inicia a gravação; soltar encerra o fluxo.
- Whisper transcreve português e inglês, com modo Automático usando `-l auto`.
- O resultado é inserido no campo original por clipboard/paste; o cursor permanece ao fim do trecho.
- O histórico, o diagnóstico e a cápsula flutuante de estados estão disponíveis.
- O áudio temporário é removido após o processamento.
- Os binários nativos atuais usam arm64 e Metal no Apple Silicon.
- Os modelos permanecem carregados nos servidores locais durante a sessão.

A cápsula flutuante foi validada visualmente durante uma gravação: fica centralizada horizontalmente no monitor ativo e próxima à parte inferior da área visível, com margem de 24 pontos.

## Arquitetura

- SwiftUI/AppKit em `Sources/VoxlyApp/`.
- `DictationCoordinator.swift`: captura, fluxo e estados.
- `Services.swift`: áudio, inserção, fallback CLI e engines locais.
- `ModelServers.swift`: ciclo de vida dos servidores locais e HTTP.
- `ContentView.swift`: modos, histórico e diagnóstico.
- `VoxlyApp.swift`: menubar, janela e cápsula flutuante.
- `Stores.swift` / `Models.swift`: persistência local e modelos de dados.

Servidores locais:

- Whisper: `127.0.0.1:18080/inference`
- Llama: `127.0.0.1:18081/completion`

Fontes nativas:

- `native/whisper.cpp/`
- `native/llama.cpp/`

## Modelos e instalação local

Executáveis e modelos ficam em `~/Library/Application Support/Voxly/Models/`:

```text
whisper-cli
whisper-server
llama-cli
llama-server
ggml-small.bin
instruct.gguf
```

Os quatro executáveis são builds arm64/Metal. O arquivo `instruct.gguf` é o symlink usado pelo modelo instruct local.

## Comandos de retomada

Abrir o app:

```sh
open /Users/ivanseibel/dev/personal/voxly/build/Voxly.app
```

Verificar os servidores:

```sh
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18081/health
```

Recompilar e empacotar:

```sh
zsh scripts/package-app.sh
```

O script usa a identidade estável `Voxly Local Development`. Não trocar por assinatura ad-hoc, pois isso faz a permissão de Acessibilidade desaparecer a cada build.

## Desempenho registrado

- Whisper nativo arm64/Metal: aproximadamente 0,90 s para 11 s de áudio após aquecimento.
- Llama arm64/Metal: aproximadamente 100 tokens/s.
- Servidores persistentes: aproximadamente 0,38 s para Whisper e 0,31 s para Llama em chamadas diretas.
- O primeiro uso pode ser mais lento por carregamento do modelo e compilação Metal.

## Histórico de correções

- A captura de logs do Whisper foi corrigida para não incluir stderr no texto transcrito.
- O modo Automático passou a enviar explicitamente `-l auto` ao Whisper.
- A inserção passou a retornar `.inserted` quando os CGEvents são criados com sucesso e `.copied` apenas no fallback.
- O modo ativo é restaurado entre sessões por meio do UUID persistido em `activeModeID`.
- Quebras de linha artificiais no texto inserido foram corrigidas.
- O refinamento local foi ajustado para usar o endpoint `/completion` com o template do modelo configurado, além de um prompt estrito para preservar fatos e evitar texto introdutório.
- O logger local `VoxlyLog` grava em `~/Library/Application Support/Voxly/voxly.log` para diagnóstico das inferências.
