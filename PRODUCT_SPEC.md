# Especificação de Produto — Voxly v1

## 1. Visão do produto

O Voxly é um aplicativo de ditado local para macOS que transforma fala em texto e o insere no campo ativo de qualquer aplicativo compatível. O usuário mantém pressionado um atalho global, fala, solta o atalho e recebe o texto transcrito — opcionalmente refinado por instruções locais — sem enviar áudio ou conteúdo a serviços de IA remotos.

O foco da v1 é oferecer uma alternativa privada e rápida a ferramentas como Wispr Flow e Spokenly para pessoas que escrevem em português e inglês em apps de trabalho, comunicação e desenvolvimento.

## 2. Público e necessidades

### Público primário

Pessoas com Mac Apple Silicon que escrevem frequentemente em campos de texto de múltiplos aplicativos e querem ditar com privacidade, sem depender de uma conexão ou conta de IA.

### Necessidades atendidas

- Ditar sem abrir uma janela ou trocar de aplicativo.
- Produzir texto fiel ou adaptado ao contexto, conforme um modo escolhido.
- Definir atalhos e instruções de escrita reutilizáveis.
- Recuperar transcrições recentes sem conservar arquivos de áudio sensíveis.
- Saber claramente quando o app está gravando, processando ou não consegue inserir o texto.

## 3. Escopo da v1

### Incluído

- Aplicativo de menubar nativo para macOS recente em Apple Silicon (M1 ou posterior).
- Ativação global por pressionar-e-segurar; Command direito é o atalho padrão e outros atalhos podem ser configurados.
- Captura de áudio, transcrição local e descarte do áudio logo após a transcrição.
- Reconhecimento otimizado para português e inglês, com seleção de idioma por modo.
- Modos salvos com atalho, idioma, instruções, modelo e ação de saída.
- Inserção automática no campo que estava focado, com cópia para a área de transferência como contingência.
- Histórico local de textos, com pesquisa e exclusão.
- Onboarding e estado de diagnóstico para permissões de Microfone e Acessibilidade.
- Download, verificação e gerenciamento local de modelos de transcrição e pós-processamento.

### Fora do escopo

- Windows, macOS Intel, iOS e Android.
- Sincronização em nuvem, contas, colaboração ou telemetria de conteúdo.
- Retenção, reprodução ou exportação de áudio.
- Ativação por alternância, duplo toque, voz, mouse ou gesto.
- Modelos externos, chaves de API ou processamento remoto.
- Automação de aplicativos, comandos de voz e execução de scripts.

## 4. Fluxo principal

1. O usuário deixa o cursor em um campo de texto de um aplicativo compatível.
2. Mantém pressionado o atalho do modo ativo; o Voxly registra o app e o foco atuais e inicia a captura.
3. A cápsula flutuante perto do cursor mostra o nível de áudio e o estado `Gravando`.
4. Ao soltar o atalho, o Voxly encerra a captura e mostra `Transcrevendo`.
5. O motor local gera o texto bruto; o áudio é removido da memória e de qualquer arquivo temporário.
6. Se o modo tiver instruções, o LLM local produz o texto final sob regras de preservação; a cápsula mostra `Ajustando`.
7. O Voxly restaura o foco original e insere o resultado. Se não puder inserir, copia o resultado e informa o usuário.
8. O histórico recebe o texto final, o texto bruto, o modo, o idioma e a data, mas nunca o áudio.

## 5. Requisitos funcionais

### 5.1 Captura e atalhos

- O Voxly deve observar atalhos globais mesmo quando não estiver em primeiro plano.
- O atalho padrão deve ser Command direito em modo pressionar-e-segurar.
- Enquanto o atalho estiver pressionado, o estado deve ser `Gravando`; sua liberação encerra a captura.
- Escape deve cancelar a gravação ou o processamento em curso e não inserir texto.
- O usuário deve poder atribuir um atalho exclusivo a cada modo salvo.
- O Voxly deve impedir atalhos duplicados e avisar quando um atalho não puder ser registrado no sistema.

### 5.2 Transcrição local

- A transcrição deve usar `whisper.cpp` com aceleração Metal e modelo local equilibrado.
- Cada modo deve definir português, inglês ou detecção entre os dois idiomas.
- O app deve manter o texto bruto para auditoria no histórico, separado do resultado otimizado.
- Caso a transcrição falhe, nenhum texto deve ser inserido e a cápsula deve exibir um erro recuperável.

### 5.3 Pós-processamento local

- Um modo sem instruções deve usar o texto bruto como resultado final.
- Um modo com instruções deve executar um modelo instruct local via `llama.cpp` com aceleração Metal.
- Toda solicitação ao LLM deve incluir regras fixas: preservar fatos, nomes, números, idioma e intenção; não inventar, resumir nem excluir informações salvo se a instrução do modo determinar explicitamente.
- O resultado do LLM deve ser tratado como falho se estiver vazio; nesse caso, o Voxly deve usar o texto bruto e informar que o refinamento não foi aplicado.

### 5.4 Modos

Cada modo deve conter:

| Campo | Descrição |
| --- | --- |
| Nome | Rótulo exibido na interface e no histórico. |
| Atalho | Combinação global única usada para iniciar a gravação. |
| Idioma | Português, inglês ou automático entre ambos. |
| Instruções | Texto de pós-processamento; pode ficar vazio. |
| Perfil de modelo | Perfil local equilibrado da v1. |
| Saída | Inserir automaticamente, com cópia de contingência. |

Os modos iniciais são:

| Modo | Instrução padrão |
| --- | --- |
| Transcrição fiel | Preservar a fala, ajustando somente pontuação e capitalização óbvias. |
| Limpar texto | Remover vícios de linguagem e organizar o texto sem alterar significado ou fatos. |
| E-mail profissional | Converter em e-mail claro e profissional, preservando conteúdo, nomes e solicitações. |
| Código/notas técnicas | Organizar como nota técnica, preservar termos, identificadores, números e blocos de código ditados. |

### 5.5 Inserção de texto

- Antes de gravar, o app deve registrar o elemento ou aplicativo que tinha foco.
- Após processar, deve tentar inserir o texto via APIs de Acessibilidade no destino original.
- Quando a inserção direta não for possível, deve preservar o clipboard anterior, copiar o resultado, tentar colar e restaurar o clipboard anterior quando seguro.
- Se não puder inserir ou colar, deve deixar o resultado no clipboard e apresentar uma mensagem clara de que o usuário precisa colar manualmente.
- Nenhum resultado deve ser inserido após cancelamento, erro de transcrição ou liberação sem áudio útil.

### 5.6 Histórico e privacidade

- O histórico deve ser local e ligado por padrão.
- Cada entrada deve armazenar texto bruto, texto final, modo, idioma, horário e resultado da inserção.
- A tela de histórico deve permitir pesquisa por texto e exclusão individual ou total.
- Áudio e arquivos temporários de áudio devem ser apagados após a transcrição, inclusive quando ela falhar ou for cancelada.
- O app não deve enviar áudio, transcrição, instruções ou histórico a serviços externos após os modelos terem sido instalados.

### 5.7 Modelos e onboarding

- O primeiro uso deve explicar que o Voxly processa conteúdo localmente e solicitar permissões de Microfone e Acessibilidade.
- O app deve baixar e verificar os modelos locais necessários antes de liberar a primeira transcrição.
- A interface deve informar progresso, espaço necessário, conclusão e falha de download.
- Se permissões ou modelos estiverem indisponíveis, o menubar e a tela principal devem mostrar o bloqueio e instruções para resolvê-lo.

## 6. Experiência e interface

### Linguagem visual

O produto deve parecer uma ferramenta silenciosa de mesa: grafite de alumínio e preto para superfícies, verde para captação ativa, âmbar para processamento, branco para texto final e azul de seleção do macOS. A interface não deve adotar um dashboard de métricas, cards genéricos ou navegação lateral como estrutura principal.

### Superfícies

- O ícone de menubar oferece acesso ao estado, modo ativo, histórico, configurações e diagnóstico.
- A cápsula de fala é a principal assinatura visual: compacta, flutuante e temporária; ela acompanha a gravação sem roubar foco.
- A janela de configuração prioriza a edição de modos e o histórico, com controles diretos e pouco ruído visual.

### Estados da cápsula

| Estado | Feedback |
| --- | --- |
| Pronto | Ícone discreto e modo ativo no menubar. |
| Gravando | Indicador verde e medidor de nível de áudio. |
| Transcrevendo | Indicador âmbar com progresso indeterminado. |
| Ajustando | Indicador âmbar e nome do modo aplicado. |
| Inserido | Confirmação breve com marca verde. |
| Copiado | Aviso breve para colar manualmente. |
| Erro | Mensagem curta, ação de recuperação e sem inserção automática. |

## 7. Requisitos não funcionais

- O app deve funcionar sem rede depois que os modelos forem instalados.
- O app deve ser responsivo durante captura e processamento, mantendo a interface e o atalho disponíveis.
- Modelos devem usar aceleração Metal e o perfil padrão deve equilibrar precisão, memória e tempo de resposta.
- Todos os dados persistentes devem ficar no armazenamento privado do app no Mac.
- A distribuição deve ser assinada e notarizada; não será publicada pela Mac App Store por depender de acesso global a teclado e Acessibilidade.

## 8. Critérios de aceite

- Command direito inicia a gravação somente enquanto estiver pressionado e sua liberação encerra o fluxo.
- O texto nunca é inserido antes da liberação do atalho.
- Um modo aplica apenas as próprias instruções e o modo `Transcrição fiel` não executa pós-processamento de reescrita.
- O resultado é inserido no campo inicialmente focado ou fica copiado com aviso explícito.
- O áudio não permanece no histórico, em cache ou em arquivos temporários após conclusão, cancelamento ou falha.
- O histórico pode ser pesquisado e apagado localmente.
- Sem rede, uma instalação com modelos já baixados continua capaz de gravar, transcrever, otimizar e inserir texto.
- Erros de permissão, modelo, transcrição e inserção são visíveis e não causam perda silenciosa do resultado.

## 9. Métricas de sucesso da v1

- O fluxo de ditado completo é concluído sem interação adicional além de pressionar, falar e soltar na maioria dos casos.
- Usuários conseguem configurar e usar ao menos um modo personalizado após o onboarding.
- Falhas de inserção preservam o resultado no clipboard em vez de descartá-lo.
- Nenhum áudio persiste após o ciclo de ditado.
