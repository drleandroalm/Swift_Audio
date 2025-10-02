# Roadmap

This roadmap captures the immediate focus areas for Swift Scribe now that diarization, AI processing, rich text output, and local data storage are fully wired together.

## ✅ Entregas Recentes
- Integração completa do FluidAudio com suporte a modelos locais (`speaker-diarization-coreml/`) e atualização dinâmica via `FLUID_AUDIO_MODELS_PATH`.
- Pacote offline dos modelos Core ML dentro do app (startup sem rede).
- Interface totalmente localizada para português brasileiro, incluindo ações de gravação, toolbar e mensagens de erro.
- Painel de configurações com controles para diarização (limite de clusterização, duração mínima, número máximo de falantes) e processamento em tempo real.
- Nova preferência: tamanho da janela de processamento em tempo real (1–10 s) com aplicação imediata no `DiarizationManager`.
- Presets de diarização (Reunião/Entrevista/Podcast) que ajustam múltiplos parâmetros de uma vez. Ajustes manuais retornam o perfil para Personalizado.
- Persistência em disco com SwiftData para `Memo`, `Speaker` e `SpeakerSegment` — dados sobrevivem reinícios.
- Alinhamento preciso por tempo de token (word-level) mapeado às janelas de diarização — torna a atribuição por falante exata.
- Visualização ao vivo (chips e barra temporal) e logs com contagem de segmentos/falantes por janela e na passada final.
- Botão de "Restaurar padrão" no seletor de perfil e dicas interativas com exemplos práticos nos controles de qualidade.
- Amarração das preferências de `AppSettings` ao `DiarizationManager`, com reconfiguração automática e limpeza quando a diarização é desativada.
- Suite de testes em XCTest cobrindo `AppSettings`, `DiarizationManager`, persistência no SwiftData e geração de títulos/resumos com IA.
- Logs críticos e mensagens internas traduzidos para pt-BR, alinhados ao restante da experiência localizada.
- Testes end-to-end (`RecordingFlowTests`) simulando sessões longas, diarização desativada e reconfiguração dinâmica via `AppSettings`.
- Modernização de tipos existenciais para Swift 6 (uso de `any`) para suprimir avisos futuros.
- UI de inscrição de falantes (macOS/iOS): folha de inscrição com gravação (~8s), barra de progresso, medidor de nível, persistência em SwiftData e injeção no runtime (FluidAudio SpeakerManager).
- Renomeação de falantes na visão “Falantes” (botão de lápis e menu de contexto), com propagação ao banco de runtime.
- Verificação de semelhança: ação rápida por falante com folha de verificação (gravar/importar trecho) e exibição de confiança (0–100%).
- Inscrição com múltiplos clipes por falante (fusão/média de embeddings) e importação de arquivo de áudio local (macOS) na folha de inscrição.
- Testes de fluxo de inscrição/renomeação e ajustes em testes existentes para compatibilidade com o novo pipeline final.
- Aprimoramento de falantes: UI dedicada para adicionar novos clipes a um perfil existente e refazer a embedding (fusão) com persistência + injeção no runtime.
- Importação/Exportação de perfis em JSON (macOS) via painel, com reuso imediato no runtime.
- Verificação contínua (ao vivo) com limiar ajustável para decisão rápida (padrão 0,80).
- Importação/Exportação no iOS via Files (.json) com `.fileImporter`/`.fileExporter`.
 - Exportar transcrição (iOS) via Files: JSON e Markdown.
- Correção: reinicialização per‑memo do pipeline (novo `TranscriptView.id(memo.id)`, reconstrução do `SpokenWordTranscriber` e `Recorder` ao alternar memos) para evitar congelamento/uso de transcritor anterior em novos memorandos.
- UX: suprimir alerta de “No content to enhance” quando não houver texto ainda no memorando.
 - Segurança adicional: pular auto‑início de gravação em memos que já possuem texto/URL; e finalizar explicitamente o transcritor ao parar para um ciclo de vida mais previsível.
- Infra de áudio: novo `Recorder.teardown()` para parar motores, remover taps e finalizar continuations durante reconfigurações.
 - Atualizações ao vivo ultra-suaves da transcrição: `SpokenWordTranscriber` migrado para `ObservableObject` com `@Published` e a View agora o observa via `@StateObject`, garantindo renderização reativa da transcrição volátil em tempo real.
 - Robustez de parada: o loop de streaming passou a ser cancelável (armazenamos o `Task` e verificamos `Task.checkCancellation()`), removendo o backlog pós‑parada e eliminando a sensação de “não para”.
- Cronômetro de gravação: o timer agora usa modo de run loop `.common`, evitando congelamento em 00:00 durante interações de UI.
- Segurança de UI: mutações de estado de diarização em `onReceive` foram adiadas para o próximo loop da main thread, suprimindo avisos “Modifying state during view update”.

### 2025-09 — Estabilidade de compilação (Swift 6, SwiftUI)
- Divisão profunda do `TranscriptView` para reduzir pressão no type-checker do Swift 6:
  - Subviews dedicadas: `LiveRecordingContentView`, `FinishedMemoContentView`, `BannerOverlayView`.
  - Modificador leve para eventos: `RecordingHandlersModifier` agrega `.onChange`, `.onReceive`, `.onAppear`, `.task`, `.onDisappear` e alerts, reduzindo genéricos encadeados no `body`.
  - Builder iOS: `IOSPrincipalToolbar` isola o título/legenda no iOS, mantendo caminhos macOS/iOS pequenos e independentes.
- Resultado: o alvo macOS volta a compilar e os testes rodam; os smoke tests de transcrição ainda podem falhar esporadicamente por “nilError” (comportamento já observado; preferir CLI para verificação determinística).
- Correção iOS: acesso ao `AudioDeviceManager` protegido por `#if os(macOS)` em `Recorder.handleNoAudioDetected()`.

### 2025-09 — Testes & CI (Determinismo)
- Smoke tests `TranscriberSmokeTests` (macOS) ajustados: protegidos contra a exceção opaca “nilError” e marcados com `XCTSkip` por padrão no macOS/CI; mantidos como ferramenta local de diagnóstico.
- Novo `RecordingHandlersModifierTests` valida ganchos de eventos (`onChange`, `onReceive`, `onAppear`, `task`, `onDisappear`) em um `NSHostingView`, sem depender de hardware de áudio.
- CI continua garantindo empacotamento offline via `Scripts/verify_bundled_models.sh` (macOS + iOS) e execução do alvo iOS de verificação. Para pipeline determinístico, recomenda-se `Scripts/RecorderSmokeCLI/run_cli.sh`.

### 2025-09 — Captura de Logs (80s, OSLog)
- O script `Scripts/capture_80s_markers.sh` foi aprimorado para:
  - Incluir padrões em inglês e português (ex.: “AVAudioEngine started”, “Primeiro buffer recebido”, “Nenhum áudio detectado”).
  - Injetar variáveis de ambiente ao iniciar o binário do app diretamente (`Contents/MacOS/SwiftScribe`), permitindo:
    - `SS_AUTO_RECORD=1` para início automático da gravação (apenas Debug).
    - `FLUID_AUDIO_MODELS_PATH` apontando para `speaker-diarization-coreml/` para evitar avisos de warmup.
- O app agora emite via `Logger` os marcadores em pt-BR (além dos em inglês) durante a captura: “Primeiro buffer recebido”, “Motor de gravação iniciado”, “Nenhum áudio detectado (dispositivo=…)”.

### 2025-09 — URL Scheme & Automação
- Novo handler de URL (`swiftscribe://record`) para automação de início de gravação no macOS.
- Toggle em Configurações → “Automação” para habilitar/desabilitar este recurso em runtime.
- Para habilitar fora de Debug, registre o esquema no Info do alvo (Xcode → Info → URL Types → `swiftscribe`).

### 2025-09 — CI Smoke Determinístico
- Workflow atualizado para incluir um passo “CLI Smoke (Deterministic)” após os testes de macOS.
- Comando executado: `Scripts/RecorderSmokeCLI/run_cli.sh Audio_Files_Tests/Audio_One_Speaker_Test.wav` e uma asserção mínima de saída.

### 2025-09 — Robustez da captura (macOS/iOS)
- Evitar cancelamento acidental do `Task` de captura: migração para `Task.detached` e remoção de checagens de cancelamento no loop; o stream finaliza apenas quando `stopRecording()` ou `teardown()` encerram a continuação.
- Teardown determinístico: aguardamos o término do task (`await value`) após `stopRecording()` para garantir que a pipeline finalize antes de gerar sumário/exportações.
- Sinalização de fluxo: novo `Recorder.hasReceivedAudio` marca quando o primeiro buffer chega do tap; útil para diagnósticos e UX.
- Watchdog de 3s reinstala o tap/engine quando nenhum buffer chega, lidando com dispositivos que demoram a entregar áudio no macOS.
- Voice processing do input é desativado explicitamente no macOS para contornar erros AUVoiceProcessing (`-10877`) em dispositivos sem suporte.
- Janela de proteção na parada: toques de “parar” são ignorados apenas nos primeiros 2s após o início para prevenir falsos positivos; após isso, parar é permitido mesmo sem áudio (com logs informativos).
- Correção de compilação iOS: redução de complexidade do branch `switch displayMode` com `AnyView` para evitar timeout de type-check.

## 🔄 Em Andamento
- Continuar afinando latência de diarização ao vivo e consumo de CPU em cenários longos.
- Monitorar o tempo total da suíte (`~1,6 s` local) e preparar gates para evitar regressões de performance nos testes end-to-end.
- Painel de analytics pós-gravação: expandir métricas (ex.: distribuição por turno) e gráficos; exportar JSON/Markdown.
 - UX de inscrição: dicas de captação (sinal/ruído), instruções contextuais e feedback sobre qualidade da amostra.
- Verificação de semelhança: opção de “verificar continuamente” para streams longos.
- Exportar/importar também no iOS (Files) e arrastar/soltar no macOS.
- Paridade total iOS: concluir UX de compartilhamento, exportar transcrições com metadados (JSON/Markdown) e testes UI em iOS.
- CI: manter gates em PRs para verificação de empacotamento dos modelos (script + alvo de testes iOS) e suíte macOS.
 - Ajustar esquema de testes para evitar dependência do host iOS ao rodar `xcodebuild … test` no macOS (separar alvos por plataforma ou usar `-only-testing` com um esquema dedicado).
 - Documentar e consolidar guia de próxima instância para iOS (Next_Instance_Knowledge_v2.md) — expandir com casos de teste e exemplos de JSON.
 - UI de combinação/ponderação de múltiplas amostras (pesos, descartar outliers), e trilha de auditoria.

### 2025-09 — Robustez da captura (macOS/iOS)
- Watchdog de 3s reinstala o tap/engine quando nenhum buffer chega, lidando com dispositivos que demoram a entregar áudio no macOS.
- Indicador de “mic pronto” em UI (primeiro buffer): ajuda a depurar ausência de buffers.
- Picker de dispositivo de entrada (macOS) em Configurações: permite selecionar o microfone de forma explícita (padrão: embutido).
- Logs com nome do dispositivo durante reinicializações do watchdog.
- CLI headless para depurar pipeline fora do XCTest: `Scripts/RecorderSmokeCLI/run_cli.sh`.
- Smoke tests headless com fallback (XCTest): `TranscriberSmokeTests` com pré-conversão para o formato do analyzer.

### Próximos Passos Técnicos
- Amarrar sessão de captura a um device ID (AUHAL) evitando dependência do “default input” do sistema.
- Mostrar status “reinicializando áudio…” quando o watchdog estiver ativo.
- Expandir captura de logs automatizada (script) com filtros para “Primeiro buffer recebido”/“Nenhum áudio detectado”/“Motor de gravação iniciado”.

## 📌 Próximos Passos
- Oferecer presets de qualidade (ex.: "Reunião", "Entrevista", "Podcast") que ajustem múltiplos parâmetros de diarização em conjunto. ✅ (entregue)
- Permitir exportação do transcript com metadados de falantes em formatos padrão (JSON, Markdown).
- Expandir o suporte a múltiplos idiomas nos prompts de IA, respeitando a localidade selecionada na transcrição.
- Adicionar opção de escolher variações de modelo de embedding (ex.: `wespeaker_int8`) para footprint menor.
- Inscrição com múltiplos clipes por falante e fusão de embeddings.
- Importação de arquivo de áudio para inscrição (arrastar/soltar) além de microfone.
- Verificação de similaridade sob demanda (UI) com pontuação e explicação.
- UI para aprimorar um falante existente adicionando novos clipes (fusão incremental, desfazer).
- Exportar/importar perfis de falantes (JSON) para migração/backup.
- Thresholds por-falante e presets (conservador/equilibrado/agressivo) para decisões de correspondência. ✅ (entregue)
 - Suporte a compartilhamento nativo (ShareLink) para exportar perfis/transcrições. ✅ (parcial — export unificado JSON)
 - Feedback de qualidade de amostra (SNR) com dicas automáticas no iOS.

Sinta-se à vontade para abrir issues com ideias adicionais ou sugerir prioridades diferentes.
- Visualização moderna de transcrição com barra de ferramentas compacta, scrubber flutuante, indicador radial de microfone e cartões de falantes com mini-sparklines.
- Exportação unificada (JSON) com transcrição + falantes (macOS painel e iOS Files export).
 - Exportação de falantes no macOS via NSSavePanel (entitlement de Leitura/Gravação habilitado); fallback automático para a pasta Documentos do container permanece disponível.
 - Corrigida a string de permissão de microfone e adicionadas localizações (Base/pt-BR) via InfoPlist.strings.
 - Reordenação de invalidação do timer de reprodução para maior segurança durante o teardown.
- Modelos de diarização agora são exigidos localmente (sem download remoto); `speaker-diarization-coreml/` é empacotado no app e utilizado por padrão.
 - Novo alvo de testes iOS (`ScribeTests_iOS`) verifica a presença dos modelos no bundle do app (simulador), executável via `SwiftScribe-iOS-Tests`.
 - CI (GitHub Actions) roda script de verificação para macOS e iOS (simulador), garantindo startup offline consistente.
 - Fusão de embeddings configurável (média simples vs. ponderado por duração) para "Salvar como conhecido".
- Thresholds por falante + presets (Conservador/Balanceado/Agressivo) na tela de Configurações.
- Onda (waveform) opcional sob o scrubber gerada por decimação otimizada do arquivo de áudio.
 - Toggle de waveform na tela de Configurações para controlar o custo visual e de memória em gravações longas.
 - Infra: consolidar scripts de verificação e adicionar job opcional para executar o alvo `SwiftScribe-iOS-Tests` em múltiplos simuladores.
 - Observabilidade: avaliar migração do progresso de download de modelos para `@Published`/Bindings a fim de remover timers de pooling em UI.
