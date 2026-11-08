# Foto Limpa

**Português** · [English](README.en.md)

Aplicativo nativo para macOS que cria cópias de fotos sem os metadados incorporados da origem e permite comparar os dados **antes × depois**. O processamento de imagens acontece no próprio Mac.

> Ferramenta de privacidade e inspeção de metadados. Não garante evitar rótulos de IA em redes sociais, não detecta nem remove marcas invisíveis nos pixels, como SynthID, e não certifica a autenticidade de uma foto.

## Propósito e utilidade

Fotos podem carregar coordenadas GPS, informações da câmera, comentários e registros de edição que não aparecem na imagem. O Foto Limpa ajuda a criar uma cópia para compartilhar, conferir quais dados mudaram e manter o arquivo original.

- Remover localização e outros metadados incorporados antes de compartilhar fotos.
- Retirar registros de câmera, edição, comentários e procedência do arquivo exportado.
- Inspecionar diferenças entre o original e a cópia processada.
- Converter fotos compatíveis para JPEG ou PNG.
- Processar imagens sem conta e sem enviar fotos a um servidor.

## Funcionalidades

- Entrada JPEG, PNG, HEIC ou TIFF, com um único quadro; saída JPEG (qualidade 95%) ou PNG.
- Reconstrução da imagem sem copiar EXIF, GPS, IPTC, XMP ou C2PA incorporado da origem.
- Inspeção estrutural de segmentos JPEG, blocos PNG e dados após o fim da imagem.
- Comparação com prévias, campos, valores, tamanho e SHA-256; estados removido, alterado, adicionado e mantido.
- Busca de campos/valores e filtro para mostrar apenas alterações.
- Relatório JSON com leitura anterior, leitura posterior e diferenças.
- De 1 a 5 passagens de decodificação, exportação e verificação; uma passagem é recomendada.
- Nome neutro aleatório opcional para a cópia.
- Verificação dos bytes e metadados cobertos pela inspeção após gravar o arquivo.
- Proteção contra sobrescrita da origem, incluindo caminhos equivalentes e links simbólicos.

A interface atual está em português; a documentação está disponível nos dois idiomas.

## Tecnologias utilizadas

| Tecnologia | Uso no projeto |
| --- | --- |
| Swift | Implementação do aplicativo e dos testes. |
| SwiftUI | Interface, estados de tela, abas, filtros e comparação. |
| AppKit | Seleção/gravação de arquivos, prévias e integração com o Finder. |
| ImageIO | Leitura das imagens, orientação, metadados e codificação JPEG/PNG. |
| CoreGraphics | Renderização de um bitmap novo em sRGB. |
| UniformTypeIdentifiers | Identificação dos formatos nos seletores de arquivo. |
| CryptoKit | Cálculo de SHA-256 para inspeção e comparação. |
| Foundation e Grand Central Dispatch | Arquivos, JSON e processamento fora da thread principal. |
| Bash, `xcrun swiftc` e `codesign` | Testes, compilação e assinatura ad hoc local. |

Usa frameworks do sistema, sem dependências de terceiros em tempo de execução.

## Requisitos

- Mac **Apple Silicon** (arm64: M1 ou posterior).
- **macOS 13 ou posterior** como versão mínima de implantação.
- Para compilar: ferramentas de desenvolvimento da Apple com `swiftc`, SDK do macOS e `codesign` disponíveis por `xcrun`.

A compilação e os testes foram verificados no ambiente de desenvolvimento disponível; não houve validação em todas as versões anteriores do macOS. O script atual gera apenas arm64.

## Baixar e usar

1. Abra [Releases](https://github.com/gsantanaoffsec/foto-limpa/releases) e baixe o ZIP da versão desejada.
2. Extraia e abra `Foto Limpa.app`. Opcionalmente, mova o aplicativo para Aplicativos.
3. Clique em **Selecionar foto…** e escolha um arquivo compatível.
4. Escolha JPEG ou PNG e o número de passagens. Comece com **1 · recomendada**.
5. Clique em **Limpar e comparar**.
6. Na aba **Antes × depois**, confira as prévias e os dados. Use **Só alterações** e a busca para filtrar a tabela.
7. Clique em **Salvar cópia…** para escolher o destino.
8. Opcionalmente, use **Salvar relatório…** para guardar a comparação em JSON.

**O relatório inclui valores originais, inclusive GPS se existir.** Guarde-o separado da foto que pretende compartilhar.

O aplicativo tem assinatura **ad hoc local**, sem certificado Developer ID ou notarização Apple. Se o macOS bloquear a abertura, consulte as opções para esse aplicativo em **Ajustes do Sistema → Privacidade e Segurança**. Não é necessário desativar as proteções gerais do sistema.

O processamento é local. O item de Ajuda sobre rótulos de IA abre uma página externa no navegador quando acionado.

## Compilar a partir do código

```bash
git clone https://github.com/gsantanaoffsec/foto-limpa.git
cd foto-limpa
bash build.sh
```

O script gera e assina `dist/Foto Limpa.app`. Para abrir:

```bash
open "dist/Foto Limpa.app"
```

Se as ferramentas da Apple ainda não estiverem instaladas, solicite a instalação com `xcode-select --install` e conclua o instalador antes de compilar.

## Executar os testes

```bash
bash test.sh
```

Os testes geram imagens sintéticas localmente e cobrem remoção de EXIF/GPS/IPTC, orientação, dimensões, transparência PNG, rejeição de arquivos inválidos e múltiplos quadros, preservação do original, proteção por link simbólico, comparação, SHA-256 e relatório JSON. Também verificam três passagens JPEG, cinco passagens PNG, contagens inválidas de passagens, blocos APP11, texto PNG, caBX e dados após o fim de um JPEG.

Os blocos C2PA sintéticos testam inspeção estrutural e descarte, **não** validação de assinaturas. Nenhum teste publica fotos em redes sociais.

## Como funciona

1. Verifica tamanho, dimensões e número de quadros.
2. Decodifica a imagem com a orientação aplicada.
3. Desenha os pixels em um bitmap novo de 8 bits em sRGB.
4. Codifica um novo JPEG/PNG sem copiar propriedades da origem.
5. Descarta blocos adicionais, mantendo a estrutura da imagem e as informações de cor permitidas.
6. Inspeciona o resultado; nas passagens adicionais, usa a saída como próxima entrada.
7. Ao salvar, relê e verifica o arquivo gravado.

Dimensões e informações técnicas necessárias, como um perfil de cor genérico, podem permanecer. A contagem de campos removidos não representa o número de sinais de IA removidos: também inclui propriedades técnicas e representações de um mesmo dado.

## Limitações

- Limite de **100 megapixels** e **250.000.000 bytes** por arquivo.
- Animações e arquivos com várias imagens são recusados. Alguns HEIC com imagens auxiliares podem exigir exportação prévia como foto estática.
- A inspeção estrutural da origem cobre JPEG/PNG. Para HEIC/TIFF, a leitura de propriedades e XMP é **parcial**, conforme informado na interface.
- A saída é **sRGB, 8 bits e SDR**: HDR, maior profundidade e cores fora de sRGB podem mudar de aparência.
- JPEG aplica recompressão e converte transparência em fundo branco. PNG preserva transparência e usa codificação sem perdas **após** a conversão do bitmap.
- Passagens adicionais podem acumular perdas em JPEG, sem garantia extra contra detecção de IA.
- SHA-256 diferente mostra que os bytes mudaram, sem provar que a imagem ficou irreconhecível.
- Não detecta/remove marcas nos pixels, não apaga registros externos de procedência e não modifica publicações existentes.
- APP11/JUMBF é tratado como possível procedência C2PA; assinaturas não são validadas. O app não cria credenciais de captura nem comprova autenticidade.
- Não criptografa fotos: um arquivo criptografado não pode ser publicado diretamente como imagem comum.

## Estrutura

```text
.
├── README.md                   # Documentação em português
├── README.en.md                # English documentation
├── Info.plist                  # Metadados do aplicativo macOS
├── Sources/
│   ├── App.swift               # Interface e fluxo de uso
│   ├── Cleaner.swift           # Decodificação, limpeza, exportação e gravação
│   └── MetadataAudit.swift     # Inspeção, comparação, SHA-256 e relatório
├── Tests/
│   └── main.swift              # Testes com imagens sintéticas
├── build.sh                    # Compila o .app para Apple Silicon
└── test.sh                     # Compila e executa os testes
```

Os diretórios gerados `.build/` e `dist/` não são versionados.
