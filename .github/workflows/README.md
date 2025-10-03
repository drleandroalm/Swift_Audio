# GitHub Actions Workflows - Requisitos do Xcode 26 Beta

## Status Atual: ⚠️ Pendente Disponibilidade do Xcode 26

Estes workflows requerem **Xcode 26+ (iOS 26/macOS 26 beta)** para execução bem-sucedida.

## Por Que os Testes São Pulados

- **Requisitos do Projeto**: Usa APIs exclusivas do iOS 26 (SpeechAnalyzer, SpeechTranscriber, FoundationModels)
- **Limitação do GitHub Actions**: Os runners fornecem Xcode 16.2 (última versão estável)
- **Formato do Arquivo de Projeto**: Versão 90 (apenas Xcode 26.1+)

## O Que Acontece Agora

Os workflows executam a cada push, mas:
1. Verificam a versão do Xcode
2. Se Xcode < 26: Pulam testes com aviso informativo
3. Se Xcode ≥ 26: Executam a suíte completa de testes

**Sem falhas**, apenas avisos informativos até que o GitHub Actions suporte o Xcode 26.

## Quando Isto Funcionará?

Automaticamente quando o GitHub Actions adicionar suporte ao Xcode 26 (esperado meados de 2026 após lançamento público).

## Alternativa: Runner Auto-hospedado

Instruções de configuração em `test_artifacts/PHASE3_CI_CD_PIPELINE_SUMMARY.md` (procurar "Self-Hosted Runner").

### Configuração Rápida de Runner Auto-hospedado

1. **Hardware**: Mac com macOS 26 beta + Xcode 26.1 beta
2. **Registrar**: Repository Settings → Actions → Runners → New self-hosted runner
3. **Modificar Workflows**:
   ```yaml
   runs-on: self-hosted  # Mudar de macos-14
   ```
4. **Segurança**: Usar Mac dedicado, habilitar atualizações automáticas, restringir a este repositório

## Workflows Disponíveis

### `ci.yml` - Testes Legados (3 jobs)
- macOS Unit Tests (ARM64)
- iOS Model Verification (Simulator)
- CLI Smoke Test (Determinístico)

**Status**: Pula testes se Xcode < 26

### `ci-test-suite.yml` - Suíte Completa de Testes (6+ jobs)
1. **macOS Build + Unit Tests** - Valida funcionalidade básica
2. **iOS Build + Tests** - Testa alvo do iOS no simulador
3. **Framework Contract Tests** - 38 testes através de 4 suítes de framework
4. **Chaos Engineering Tests** - 16 cenários de resiliência com pontuação automática
5. **Performance Benchmarks** - Detecção de regressão (falha build se queda >10%)
6. **Generate Reports + Deploy** - Dashboard HTML com Chart.js + GitHub Pages

**Status**: Pula testes se Xcode < 26 (Jobs 1-5)

**Job 6** (Generate Reports): Sempre executa mas gera placeholder HTML se nenhum teste executou.

## Testes Locais (Recomendado)

Execute a suíte completa de testes localmente com Xcode 26.1+:

```bash
# Testes macOS (18 testes, ~1.6s)
xcodebuild -scheme SwiftScribe -destination 'platform=macOS,arch=arm64' test

# Testes do simulador iOS
xcodebuild -scheme SwiftScribe -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Teste de smoke CLI
Scripts/RecorderSmokeCLI/run_cli.sh Audio_Files_Tests/Audio_One_Speaker_Test.wav

# Verificar modelos empacotados
Scripts/verify_bundled_models.sh
```

## Linha do Tempo

- **Agora**: Workflows pulam testes no GitHub Actions (Xcode 16.2)
- **Local**: Suíte completa de testes executada com Xcode 26.1 beta
- **Futuro**: Ativação automática quando o GitHub Actions adicionar Xcode 26 (meados de 2026)

## Resolução de Problemas

### "Tests Skipped (Xcode 26 Required)" Aviso

**Esperado**: Este é o comportamento correto. Os workflows detectam Xcode < 26 e pulam graciosamente para evitar falhas.

**Ação Necessária**: Nenhuma. Os testes executarão automaticamente quando o Xcode 26 estiver disponível.

### Quero Executar CI Agora

**Opção 1**: Configure um runner auto-hospedado (veja acima)

**Opção 2**: Execute testes localmente com Xcode 26.1+ (veja comandos acima)

### O Workflow Mostra Como "Sucesso" Mas Não Executou Testes

**Esperado**: Este é comportamento correto. O workflow pula graciosamente em vez de falhar.

**Detalhes**: Procurar por avisos "Tests Skipped (Xcode 26 Required)" nos logs do workflow.

## Detalhes Técnicos

### Lógica de Verificação de Versão

Cada job executa este check:

```yaml
- name: Check Xcode Version Compatibility
  id: xcode-check
  run: |
    XCODE_VERSION=$(xcodebuild -version | head -1 | awk '{print $2}')
    MAJOR_VERSION=$(echo $XCODE_VERSION | cut -d. -f1)

    if [ "$MAJOR_VERSION" -lt 26 ]; then
      echo "should_skip=true" >> $GITHUB_OUTPUT
    else
      echo "should_skip=false" >> $GITHUB_OUTPUT
    fi
```

### Etapas Condicionais

Todas as etapas de build/test incluem:

```yaml
if: steps.xcode-check.outputs.should_skip == 'false'
```

### Avisos Informativos

Avisos do GitHub Actions são exibidos com:

```yaml
echo "::notice title=Tests Skipped (Xcode 26 Required)::..."
```

## Contribuindo

Ao modificar workflows:
1. Mantenha os checks de versão do Xcode em todos os jobs que compilam código
2. Use `if: steps.xcode-check.outputs.should_skip == 'false'` em etapas de build/test
3. Teste localmente antes de fazer push
4. Verifique a sintaxe do workflow: `brew install act && act -n`

## Mais Informações

- **Resumo Completo da Fase 3**: `test_artifacts/PHASE3_CI_CD_PIPELINE_SUMMARY.md`
- **Documentação do Projeto**: `CLAUDE.md`
- **Logs de Workflow**: Actions tab → Workflow runs → Download logs
