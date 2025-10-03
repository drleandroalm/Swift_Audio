# Swift Scribe - AI-Powered Speech-to-Text Private Transcription App for iOS 26 & macOS 26+
[![Swift](https://img.shields.io/badge/Swift-6.1+-orange.svg)](https://swift.org) ![Build Target](https://img.shields.io/badge/macOS-ARM64-success)

> **Real-time voice transcription, advanced speaker diarization, on-device AI processing, and intelligent note-taking exclusively for iOS 26 & macOS 26 and above**

Uses Apple's new Foundation Model Framework and SpeechTranscriber. Requires macOS 26 to run and compile the project. The goal is to demonstrate how easy it is now to build local, AI-first apps.

The goal of this is mostly to act as an example for others looking to work with the new models and [FluidAudio](https://github.com/FluidInference/FluidAudio). We will probably not actively maintain this unless there's significant traction. If you have problem, please consider joining our discord to chat more about this! 

[![Discord](https://img.shields.io/badge/Discord-Join%20Chat-7289da.svg)](https://discord.gg/WNsvaCtmDe)

## 🎯 Overview

**Swift Scribe** is a privacy-first, AI-enhanced transcription application built exclusively for iOS 26/macOS 26+ that transforms spoken words into organized, searchable notes with professional-grade speaker identification. Using Apple's latest SpeechAnalyzer and SpeechTranscriber frameworks (available only in iOS 26/macOS 26+) combined with FluidAudio's advanced speaker diarization and on-device Foundation Models, it delivers real-time speech recognition, intelligent speaker attribution, content analysis, and advanced text editing capabilities.

Live transcription updates are now driven by an `ObservableObject` transcriber with `@Published` properties, observed via `@StateObject` in SwiftUI. This yields ultra‑smooth volatile text rendering while recording, with safe main‑thread updates.


### 📦 FluidAudio Integration (No Packages, Offline‑Only)

- FluidAudio is vendored directly under `Scribe/Audio/FluidAudio/` (diarizer + minimal shared utilities). There is no Swift Package dependency.
- The app target operates strictly offline for diarization. Model resolution order:
  1) `FLUID_AUDIO_MODELS_PATH` (if set)
  2) App bundle resource `speaker-diarization-coreml/`
  3) Repo folder `speaker-diarization-coreml/`
- ASR and VAD sources remain in‑repo but are compiled into a separate static library target `FluidAudio-ASR` (not linked to the app). This preserves code without impacting the app module or its concurrency guarantees.
- See `Flui_Audio_Integration.md` for a step‑by‑step log of the integration.

### 🎙️ Microphone Selection + 16 kHz Pipeline

- Smart Microphone Selector (default): mimics the operating system’s current microphone selection. On macOS, the app prefers the built‑in microphone when possible.
- Manual Override (Settings → Microphone): toggle “Selecionar microfone manualmente” to pick an input from the available sources. When enabled, this bypasses the smart selector.
- Latency‑optimized conversion to 16 kHz:
  - The input tap is installed at the device’s native format (e.g., 48 kHz on Bluetooth) for stability; a reusable AVAudioConverter converts each buffer to 16 kHz mono Float32 for ML consumers and on‑disk storage.
  - Bluetooth inputs use a slightly larger tap buffer (4096) to reduce HAL overloads; other inputs use 2048.


![Swift Scribe Demo - AI Speech-to-Text Transcription](Docs/swift-scribe.gif)

![Swift Scribe Demo - AI Speech-to-Text Transcription iOS](Docs/phone-scribe.gif)

## 🛠 Technical Requirements & Specifications

### **System Requirements**
- **iOS 26 Beta or newer** (REQUIRED - will not work on iOS 25 or earlier)
- **macOS 26 Beta or newer** (REQUIRED - will not work on macOS 25 or earlier)  
- **Xcode Beta** with latest Swift 6.2+ toolchain
- **Swift 6.2+** programming language
- **Apple Developer Account** with beta access to iOS 26/macOS 26
- **Microphone permissions** for speech input


## 🚀 Installation & Setup Guide

### **Development Installation**

1. **Clone the repository:**

   ```bash
   git clone https://github.com/seamlesscompute/swift-scribe
   cd swift-scribe
   ```

2. **Open in Xcode Beta:**

   ```bash
   open SwiftScribe.xcodeproj
   ```

3. **Configure deployment targets** for iOS 26 Beta/macOS 26 Beta or newer

4. **Build and run** using Xcode Beta with Swift 6.2+ toolchain

### Persistent Storage (SwiftData)
- Data is now persisted to disk using SwiftData with a container that includes `Memo`, `Speaker`, and `SpeakerSegment`. Your recordings, speakers and analytics survive app restarts. No additional setup is required.

### Exact Speaker Attribution
- The final speaker attribution uses precise token-time alignment: each word’s `audioTimeRange` is mapped to the diarization segment covering its timestamp. This produces exact color spans and accurate “Falantes” text por segmento.
- A mesma coloração precisa pode ser aplicada ao texto principal em tempo real (toggle em Configurações > Exibições e Analytics).

### Post-Recording Analytics
- The “Falantes” view includes an analytics panel (toggle): per‑speaker total time, number of turns, and percentage of the session with a mini bar chart.
- Feature toggles are available under Configurações > Exibições e Analytics.

### 🎙️ Inscrição, verificação, aprimoramento e renomeação de falantes
- A partir da visão “Falantes”, clique em “Inscrever falante” para abrir uma folha de inscrição.
- Digite o nome do falante, pressione “Gravar” e fale por ~8 segundos (barra de progresso exibida), depois “Parar” e “Salvar”. Também é possível:
  - Acumular várias amostras (capturando múltiplos clipes) antes de salvar; as embeddings são fundidas automaticamente (média) para um perfil mais robusto.
  - Importar um arquivo de áudio local (macOS: WAV/M4A/MP3/CAF/AIFF) para usar como amostra.
- O perfil do falante (nome + embedding) é persistido no SwiftData, e é injetado no runtime do diarizador para reconhecimento imediato e consistente.
- Para verificar se um trecho de áudio corresponde a um falante salvo, use “Verificar semelhança” no menu do chip do falante: grave ou importe um trecho curto e veja a confiança (0–100%).
- Para renomear um falante existente, use o botão de lápis no chip do falante (ou o menu de contexto → Renomear).
- Para aprimorar um falante existente com novas amostras, use “Aprimorar” no menu do chip. Grave/importe um ou mais clipes, aplique, e a embedding será fundida com a anterior para maior robustez.

### 🔁 Importar/Exportar perfis de falantes (macOS)
- “Exportar” (no cabeçalho da visão Falantes) gera um JSON com os perfis (`id`, `nome`, `cor`, `embedding`).
- “Importar” carrega perfis do JSON e injeta no runtime para uso imediato.

⚠️ **Note**: Ensure your device is running iOS 26+ or macOS 26+ before installation.

### Offline Model Assets (No Network Required)

Swift Scribe bundles the full diarization model suite inside the app for fully offline startup:

- `speaker-diarization-coreml/` is packaged into the app bundle and includes:
  - `pyannote_segmentation.mlmodelc` (speech activity segmentation)
  - `wespeaker_v2.mlmodelc` (speaker embeddings)
  - Additional variants (`wespeaker.mlmodelc`, `wespeaker_int8.mlmodelc`) and `.mlpackage` manifests

At runtime, the app resolves models in this order:

1) `FLUID_AUDIO_MODELS_PATH` environment override
2) App bundle resource `speaker-diarization-coreml/`
3) Repository checkout `speaker-diarization-coreml/` (development only)

No download is attempted when the bundle assets are present. This guarantees diarization works entirely offline.

## 📋 Use Cases & Applications

**Transform your workflow with AI-powered transcription:**

### **Business & Professional**
- 📊 **Meeting transcription** with automatic speaker identification and minute generation
- 📝 **Interview recording** with real-time speaker diarization and attribution
- 💼 **Business documentation** with speaker-tagged content and report creation
- 🎯 **Sales call analysis** with participant tracking and follow-up automation

### **Healthcare & Medical**
- 🏥 **Medical dictation** and clinical documentation
- 👨‍⚕️ **Patient interview transcription** with medical terminology
- 📋 **Healthcare report generation** and chart notes
- 🔬 **Research interview analysis** and coding

### **Education & Academic**
- 🎓 **Lecture transcription** with chapter segmentation
- 📚 **Study note creation** from audio recordings
- 🔍 **Research interview analysis** with theme identification
- 📖 **Language learning** with pronunciation feedback

### **Legal & Compliance**
- ⚖️ **Court proceeding transcription** with timestamp accuracy
- 📑 **Deposition recording** and legal documentation
- 🏛️ **Legal research** and case note compilation
- 📋 **Compliance documentation** and audit trails

### **Content Creation & Media**
- 🎙️ **Podcast transcription** with automatic speaker labeling and show note generation
- 🎬 **Video content scripting** with professional speaker diarization
- ✍️ **Article writing** from multi-speaker voice recordings
- 📺 **Content creation workflows** with speaker-attributed production notes

### **Accessibility & Inclusion**
- 🦻 **Real-time captions** for hearing-impaired users
- 🗣️ **Speech accessibility tools** with customizable formatting
- 🌐 **Multi-language accessibility** support
- 🎯 **Assistive technology integration**

## 🏗 Project Architecture & Code Structure

```
Scribe/                     # Core application logic and modules
├── Audio/                  # Audio capture, processing, and FluidAudio speaker diarization
├── Transcription/         # SpeechAnalyzer and SpeechTranscriber implementation
├── AI/                    # Foundation Models integration and AI processing
├── Views/                 # SwiftUI interface with rich text editing
├── Models/                # Data models for memos, transcription, speakers, and AI
├── Storage/               # Local data persistence and model management
└── Extensions/            # Swift extensions and utilities
```

**Key Components:**

- **Audio Engine** - Real-time audio capture and preprocessing
- **Speech Pipeline** - SpeechAnalyzer integration and transcription flow
- **Speaker Diarization** - FluidAudio integration for professional speaker identification
- **AI Processing** - Foundation Models for content analysis
- **Rich Text System** - AttributedString with speaker attribution and advanced formatting
- **Data Layer** - SwiftData integration with speaker models and local storage
- **Localization & Settings** - Interface em português brasileiro com painel de ajustes para diarização e processamento em tempo real

## ⭐ Advanced Features

### **🎤 Professional Speaker Diarization**
- **FluidAudio Integration**: Industry-grade speaker identification and clustering
- **Research-Grade Performance**: Competitive with academic benchmarks (17.7% DER on AMI dataset)
- **Real-time Processing**: Live speaker identification during recording with minimal latency
- **Speaker Attribution**: Color-coded transcription with confidence scores and timeline mapping

### **🧠 Intelligent Speaker Management**
- **Automatic Speaker Detection**: No manual configuration required
- **Speaker Persistence**: Consistent speaker identification across recording sessions  
- **Visual Attribution**: Rich text formatting with speaker-specific colors and metadata
- **Speaker Analytics**: Detailed insights into speaking patterns and participation

### **🔒 Privacy-First Architecture**
- **Fully On-Device**: All processing happens locally - no cloud dependencies
- **Zero Data Transmission**: Audio and speaker data never leave your device
- **Secure Storage**: Speaker embeddings and models stored securely with SwiftData
- **Complete Offline Operation**: Works without internet connectivity

### **🇧🇷 Localização e Configurações Inteligentes**
- Interface completa em português brasileiro, incluindo fluxos de gravação, visualização de falantes e preferências.
- Painel de configurações com controles de diarização (limite de clusterização, duração mínima, número máximo de falantes), alternância de processamento em tempo real e tamanho da janela de processamento em tempo real (1–10 s).
- Presets de perfil de diarização: "Reunião" (múltiplos falantes, janelas curtas), "Entrevista" (dois falantes, segmentos mais longos) e "Podcast" (2–4 falantes com equilíbrio de estabilidade e troca). Ajustes manuais passam o perfil para "Personalizado".
- Botão "Restaurar padrão" reaplica rapidamente os valores do perfil selecionado (desativado no modo Personalizado).
- Dicas interativas: explica o impacto do limite de agrupamento e da duração mínima com exemplos práticos e simples.
- Preferências persistidas via SwiftData + `UserDefaults`, aplicadas automaticamente ao `DiarizationManager` durante e após a captura.
- Compatível com modelos locais em `speaker-diarization-coreml/` ou em caminhos personalizados via `FLUID_AUDIO_MODELS_PATH`.
- Prompts de IA são gerados pelo `DefaultMemoAIContentGenerator` com instruções em português brasileiro para títulos e resumos.

## ✅ Testes Automatizados
- `ScribeTests/ScribeTests.swift`: garante que `AppSettings` carregue valores padrão corretos e reflita alterações de execução.
- `ScribeTests/DiarizationManagerTests.swift`: cobre processamento em tempo real, finalização manual, validação de áudio e guarda auxiliares ao injetar diarizadores simulados.
- `ScribeTests/SwiftDataPersistenceTests.swift`: valida a persistência de `Speaker`/`SpeakerSegment` em um contêiner SwiftData em memória, e o reaproveitamento de perfis existentes.
- `ScribeTests/MemoAIFlowTests.swift`: exercita o fluxo de IA para títulos e resumos com geradores simulados, incluindo fallbacks localizados.
- `ScribeTests/OfflineModelsVerificationTests.swift`: verifica a presença dos diretórios de modelos (`pyannote_segmentation.mlmodelc`, `wespeaker_v2.mlmodelc`) dentro do bundle do app, garantindo startup offline.
- `ScribeTests/RecordingFlowTests.swift`: simula sessões extensas, diarização desativada e reconfiguração dinâmica de preferências usando transcritor e diarizador falsos.

### 2025-09 Fixes — Robustez de Gravação
- O ciclo de captura agora roda em `Task.detached` sem checar cancelamentos, evitando abortos espúrios causados por ruído do HAL.
- `stopRecording()` aguarda o término do task (`await value`) antes de gerar sumário/IA, garantindo teardown limpo.
- Foi adicionado `Recorder.hasReceivedAudio` para sinalizar a chegada do primeiro buffer e auxiliar diagnósticos.
- Watchdog de 3s reinicia o engine automaticamente se nenhum buffer chegar (reinstala tap e motor sem encerrar a captura), lidando com falhas transitórias do HAL.
- No macOS desativamos explicitamente o modo de voice processing do input (`setVoiceProcessingEnabled(false)`) para evitar erros `AUVoiceProcessing` (-10877) que travavam a captura em hardwares sem suporte.
- Indicador visual de “mic pronto” (primeiro buffer) no cabeçalho.
- Picker de dispositivo de entrada (macOS) na tela de Configurações (padrão: embutido).

### Headless / Smoke
- `Scripts/RecorderSmokeTest/run_smoke_test.sh`: executa `TranscriberSmokeTests` (XCTest), com pré-conversão para o formato do analyzer.
- `Scripts/RecorderSmokeCLI/run_cli.sh`: roda uma CLI Swift que imprime `[CLI][volatile]` e `[CLI][final]` para um WAV conhecido.
- Observação: em macOS há flutuações do XCTest ao finalizar (`nilError`) com o pipeline da Apple. No CI e em execuções determinísticas, prefira a CLI (`RecorderSmokeCLI`). Os testes de smoke no macOS são marcados para `XCTSkip` por padrão.

### Captura de Logs 80s (OSLog)
- `Scripts/capture_80s_markers.sh`: compila, inicia o binário do app diretamente (`Contents/MacOS/SwiftScribe`), coleta 80s de OSLog e imprime marcadores.
- Variáveis de ambiente suportadas:
  - `SS_AUTO_RECORD=1` (apenas Debug) — inicia a gravação automaticamente ao abrir.
  - `FLUID_AUDIO_MODELS_PATH=/caminho/para/speaker-diarization-coreml` — evita aviso de warmup quando a versão Debug procura no bundle.
- Marcadores em inglês e pt‑BR são analisados: “AVAudioEngine started”, “Recording session starting”, “No audio detected”, “Recorder did stop with cause”, “Diarization manager initialized”, “Motor de gravação iniciado”, “Primeiro buffer recebido”, “Nenhum áudio detectado”, `dispositivo=`.

### Auto‑record e modo headless (Debug)
- Defina `SS_AUTO_RECORD=1` para que o app crie um novo memorando, selecione a tela de gravação e inicie automaticamente ao abrir.
- Alternativamente, passe o argumento `--headless-record` na linha de comando do app para o mesmo efeito.
- Em macOS, o gravador passa a “vincular” o dispositivo de entrada atual e reassertá‑lo em reinícios do watchdog, reduzindo oscilação do HAL.

### Xcode 26.1 — Alinhamento de Build Settings
- Projeto:
  - Debug: `SWIFT_COMPILATION_MODE=singlefile`, `SWIFT_STRICT_CONCURRENCY=complete`
  - Release: `SWIFT_COMPILATION_MODE=wholemodule`, `SWIFT_OPTIMIZATION_LEVEL=-O`, `SWIFT_STRICT_CONCURRENCY=complete`
  - `CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED=YES`
- Alvo App:
  - Release: `STRIP_INSTALLED_PRODUCT=YES`
  - (Demais recomendações já habilitadas)
- A janela de proteção para toque de parada é de 2s após o início; depois disso, parar é permitido mesmo sem buffers recebidos (duplo toque confirma).
- Em iOS, o comutador de modos no `TranscriptView` foi simplificado com `AnyView` para reduzir a complexidade do type‑checker.

Execute `xcodebuild -scheme SwiftScribe -destination 'platform=macOS' test` após alterações para garantir que todas as suítes passem. A execução local atual cobre 18 testes em ~1,6 s em um Mac arm64.

### 🚀 CI/CD Pipeline e Performance Tracking

✅ **Status: CI Totalmente Funcional com macOS 26 Runner**

Os workflows do GitHub Actions estão **ativos e funcionando** usando o runner `macos-26-arm64`:
- **Runner**: macOS 26 ARM64
- **Xcode Disponível**: 26.0 (build 17A324) + 16.4
- **Compatibilidade**: ✅ Projeto requer iOS 26.0/macOS 26.0 (deployment targets)

**Workflows executam automaticamente** em cada push para `main` ou PR.

**Testes Locais**: Também suportados com Xcode 26.0+ (veja comandos abaixo).

---

**GitHub Actions Workflow** (`.github/workflows/ci-test-suite.yml`):
- **6 jobs paralelos** executados em cada push para `main` ou PR
  1. macOS Build + Testes de Unidade (ARM64)
  2. iOS Build + Testes no Simulador (iPhone 16 Pro)
  3. Testes de Contrato de Frameworks (38 testes: Speech, AVFoundation, CoreML, SwiftData)
  4. Testes de Engenharia de Caos (16 cenários de resiliência)
  5. Benchmarks de Performance + Detecção de Regressão
  6. Geração de Relatórios HTML + Deploy no GitHub Pages

**Detecção Automática de Regressão**:
- Build falha se o Resilience Score cair >10%
- Rastreamento histórico em banco SQLite (`test_artifacts/performance_trends.db`)
- Alertas para cenários com falhas novas ou scores críticos (<50)

**Dashboard Interativo**:
- Gráficos com Chart.js: score trend, scores por categoria, pass rates de cenários
- Deploy automático no GitHub Pages: `https://drleandroalm.github.io/Swift_Audio/`
- Atualizado a cada push para `main`

**Scripts**:
```bash
# Registrar resultados no banco de dados
./Scripts/record_test_run.sh --scorecard test_artifacts/ResilienceScorecard.json

# Detectar regressões (exit code 1 se houver issues críticos)
./Scripts/detect_regressions.swift check

# Gerar dashboard HTML
./Scripts/generate_html_report.swift --output test_artifacts/html_report

# Visualizar localmente
open test_artifacts/html_report/index.html
```

**Documentação Completa**: Ver `test_artifacts/PHASE3_CI_CD_PIPELINE_SUMMARY.md`

## 🔧 Build & Test Rápidos

- macOS (ARM64) build: `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' build`
- macOS tests: `xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' test`
- iOS Simulator build: `xcodebuild -scheme SwiftScribe -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
 - iOS Simulator tests: `xcodebuild -scheme SwiftScribe-iOS-Tests -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test`

## 📦 Modelos Empacotados (Offline-First)

- Os modelos Core ML de diarização são empacotados no aplicativo via `speaker-diarization-coreml/` (referência de pasta na fase de recursos). O app inicia totalmente offline.
- Ordem de resolução: `FLUID_AUDIO_MODELS_PATH` → bundle do app `speaker-diarization-coreml/` → pasta do repositório. Downloads remotos estão desativados por padrão; ausência local gera erro de configuração claro.

## 🧪 Verificação de CI dos Modelos

- O script `Scripts/verify_bundled_models.sh` compila macOS e iOS (simulador) e verifica a presença de `pyannote_segmentation.mlmodelc` e `wespeaker_v2.mlmodelc` (incluindo `coremldata.bin`) dentro dos bundles gerados.
- O workflow do GitHub Actions `.github/workflows/ci.yml` executa automaticamente essa verificação em pushes/PRs.
  - Inclui um alvo de testes específico do iOS (`ScribeTests_iOS`) para validar a presença dos modelos no bundle do simulador.
  - Opcional: você pode adicionar um passo para rodar a CLI de smoke (`Scripts/RecorderSmokeCLI/run_cli.sh`) sobre um WAV de referência para cobertura determinística do pipeline de transcrição, evitando a flutuação de finalize no XCTest do macOS.

### Registro do Esquema de URL (swiftscribe)

Para habilitar `swiftscribe://record` fora de builds de Debug (e permitir que o sistema abra o app via URL), registre o esquema no Info do alvo:

1) No Xcode, selecione o alvo do app → aba “Info”.
2) Em “URL Types”, clique em “+” e preencha:
   - Identifier: `com.swift.examples.scribe.urlscheme` (qualquer string única)
   - URL Schemes: `swiftscribe`
   - Role: `Editor`
3) Compile e rode. Agora `swiftscribe://record` aciona o handler no app.

Notas:
- A alternância “Permitir acionar gravação via URL” em Configurações controla o comportamento no runtime (pode desabilitar a automação).
- Em macOS, o handler posta uma notificação interna que navega para o memo e inicia a gravação.

#### Snippet Info.plist (alternativa manual)

Se preferir editar o Info.plist manualmente, adicione uma entrada `CFBundleURLTypes` conforme abaixo:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.swift.examples.scribe.urlscheme</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>swiftscribe</string>
    </array>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
  </dict>
  <!-- opcional: adicionar mais esquemas no futuro -->
  </array>
```

Após salvar, faça um clean build e execute o app. O sistema passa a reconhecer `swiftscribe://record` como uma URL válida para abrir o app.

## 💾 Exportação de Falantes (macOS)

- Exportações de transcrição/unificada usam `NSSavePanel` (com direito de Leitura/Gravação habilitado). A exportação de falantes também usa `NSSavePanel` e, caso falhe/indisponível, cai para a pasta Documentos do container com revelação no Finder.

## 🗺 Development Roadmap & Future Features

> Confira o estado atual e os próximos marcos em [`ROADMAP.md`](ROADMAP.md).

### **Phase 1: Core Features** ✅ **COMPLETED**

- ✅ Real-time speech transcription
- ✅ On-device AI processing  
- ✅ Rich text editing
- ✅ **Professional speaker diarization** with FluidAudio integration
- ✅ **Speaker attribution** and visual formatting
- ✅ Fully offline startup via bundled Core ML models
- ✅ Live diarization updates with adjustable processing window

### **Phase 2: Advanced Features** 

- 🔊 **Output audio tap** for system audio capture
- 🌐 **Enhanced multi-language** support
- 📊 **Advanced analytics** and speaker insights
- 🎯 **Speaker voice profiles** and personalization

## 📄 License & Legal

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for complete details.

## 🙏 Acknowledgments & Credits

- **Apple WWDC 2025** sessions on SpeechAnalyzer, Foundation Models, and Rich Text editing
- **Apple Developer Frameworks** - SpeechAnalyzer, Foundation Models, Rich Text Editor
- **FluidAudio** - Professional speaker diarization and voice identification technology

## 🚀 Getting Started with AI Development Tools

**For Cursor & Windsurf IDE users:** Leverage AI agents to explore the comprehensive documentation in the `Docs/` directory, featuring complete WWDC 2025 session transcripts covering:

- 🎤 **SpeechAnalyzer & SpeechTranscriber** API implementation guides
- 🤖 **Foundation Models** framework integration
- ✏️ **Rich Text Editor** advanced capabilities  
- 🔊 **Audio processing** improvements and optimizations

---

**⭐ Star this repo** if you find it useful! | **🔗 Share** with developers interested in AI-powered speech transcription
### iOS Import/Export (Files)
- Na visão “Falantes” no iOS, use os botões de Exportar/Importar (ícones de upload/download) para salvar/carregar perfis de falantes (.json) via app Arquivos.
- O export gera um JSON com `id`, `nome`, `cor` e `embedding` por falante. A importação adiciona/atualiza perfis e injeta no runtime do diarizador.

### iOS Exportar Transcrição (Files)
- Ainda na visão “Falantes”, toque em “Exportar transcrição” e escolha entre JSON (segmentos com `speakerName`, início/fim, confiança, texto) ou Markdown (transcrição etiquetada por falante).
