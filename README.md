# Voxly

MVP macOS local: segure Command direito, fale, solte; Voxly transcreve, opcionalmente ajusta, tenta inserir resultado no campo original. Áudio temporário é removido após processamento. Um atalho global fixo; modos alteram idioma/instruções.

## Estado

Ditado, inserção no cursor, histórico, permissões, modelos locais e aceleração arm64/Metal estão funcionando. Performance melhorou consideravelmente após trocar binários Homebrew x86 por builds nativos arm64/Metal e servidores persistentes.

O estado atual e o histórico técnico estão em [HANDOFF.md](HANDOFF.md). Pendências abertas ficam em [BACKLOG.md](BACKLOG.md).

## Rodar

```sh
swift run Voxly
```

## Motores locais

Coloque executáveis e modelos em `~/Library/Application Support/Voxly/Models/`:

```text
whisper-cli        # whisper.cpp compilado com Metal
ggml-small.bin     # modelo Whisper
```

`llama-cli` e `instruct.gguf` são opcionais: habilitam limpeza/e-mail/notas. Sem eles, Voxly preserva texto bruto. Depois, libere Microfone e Acessibilidade em Diagnóstico. Nenhum conteúdo é enviado por Voxly.

O app inicia servidores locais persistentes para Whisper e Llama quando os binários nativos estão instalados. Isso evita recarregar modelos a cada ditado. Os servidores escutam somente em `127.0.0.1` nas portas `18080` e `18081`.

## Retomada

Leia [HANDOFF.md](HANDOFF.md) primeiro. Consulte [BACKLOG.md](BACKLOG.md) para verificar pendências abertas.
