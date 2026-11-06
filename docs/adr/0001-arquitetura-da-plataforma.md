# ADR-0001: Arquitetura da plataforma KOracle (compartilhamento de tela)

**Status:** Proposto
**Data:** 2026-10-31
**Decisores:** Felipe D. Silva

---

## 1. Contexto

KOracle é uma plataforma dedicada exclusivamente a compartilhamento de tela em tempo real, com experiência próxima ao "Go Live" do Discord: um usuário transmite uma tela/janela (com áudio da aplicação) e outros assistem com baixa latência.

Estado atual dos repositórios (todos recém-criados, apenas scaffold):

| Repositório | Tipo | Observações |
|---|---|---|
| `KOracle` | App Flutter | Plataformas: android, ios, macos, windows, linux, web. `lib/main.dart` padrão. |
| `KOracleEngine` | Plugin Flutter (`koracle_engine`) | Plataformas: android (Kotlin), ios + macos (`sharedDarwinSource`, Swift Package, iOS 15 / macOS 12), windows (C++), linux (C++). Usa `plugin_platform_interface` + MethodChannel padrão. Sem web. |
| `KODevUI` | Package Flutter (`kodev_ui`) | Design system compartilhado entre apps. Vazio. |

Ambiente: Flutter 3.47.9 / Dart SDK ^3.13.

Proposta inicial do autor: UI em Flutter; um plugin (KOracleEngine) com implementação nativa por plataforma (Swift para Darwin, Kotlin para Android etc.) responsável pelo compartilhamento de tela.

### 1.1 O que "compartilhar tela como o Discord" exige de verdade

Um sistema desses não é um problema de captura; é um problema de **mídia em tempo real sobre a internet**. A cadeia completa é:

```
 [Captura] -> [Conversão/escala] -> [Encode HW] -> [Empacotamento RTP] -> [Criptografia SRTP]
     -> [Controle de congestionamento + FEC/NACK] -> [NAT traversal ICE/TURN] -> [SFU]
     -> [Rede do viewer] -> [Jitter buffer] -> [Decode HW] -> [Render em textura Flutter]
```

Além disso, fora do caminho da mídia:

- Sinalização (quem está na sala, quem transmite, negociação de codecs).
- Identidade, salas/convites, permissões.
- Presença em tempo real.
- Observabilidade de qualidade (QoE): bitrate, perda, RTT, FPS, freezes.
- Infra distribuída por região (latência importa mais que throughput).

Discord, como referência: usa WebRTC (fork do libwebrtc integrado num media engine C++ compartilhado entre todas as plataformas), SFUs próprios por região, gateway WebSocket para eventos e, desde 2024, E2EE de áudio/vídeo (protocolo DAVE, baseado em MLS). O ponto importante: **o Discord não reescreveu transporte/codec por plataforma**. O código específico por plataforma é a captura e a integração com o SO; o resto é um núcleo único.

### 1.2 Requisitos

Funcionais (MVP):

1. Criar sala e convidar por link.
2. Listar fontes (telas e janelas) com thumbnails; escolher uma.
3. Transmitir vídeo da fonte + áudio do sistema/aplicação.
4. Viewers entram e assistem; opt-in por stream ("clicar para assistir", como o Discord — não consome banda até assistir).
5. Presets de qualidade: 720p30, 1080p30, 1080p60, "Fonte".
6. Fullscreen, pop-out, indicador de viewers.
7. Reconexão automática e adaptação à rede.

Não funcionais:

| Requisito | Alvo |
|---|---|
| Latência glass-to-glass | < 300 ms p95 (WebRTC típico: 100–250 ms na mesma região) |
| Viewers por stream | 1–50 no MVP (SFU). Centenas+ exige outra estratégia (seção 6.5) |
| Qualidade | 1080p60 em ~6 Mbps; texto legível em 1080p30 |
| CPU do streamer | Encode por hardware obrigatório; < 15% CPU em 1080p60 numa máquina moderna |
| Disponibilidade | Falha de um SFU derruba só as salas nele; cliente reconecta em < 5 s |
| Privacidade | Tráfego criptografado sempre (DTLS-SRTP); E2EE como fase posterior |

---

## 2. Decisão

1. **Transporte de mídia: WebRTC.** Não implementar protocolo próprio de transporte, controle de congestionamento, FEC, jitter buffer ou NAT traversal.
2. **Topologia: SFU (Selective Forwarding Unit) self-hosted**, começando com **LiveKit Server** (open source, Apache 2.0, Go/Pion). Mediasoup fica como alternativa.
3. **Cliente: `livekit_client` (Flutter) sobre `flutter_webrtc`** como base de mídia no app.
4. **KOracleEngine passa a ser uma camada fina, não um engine de mídia.** Responsabilidades:
   - Fachada Dart única para o app (`KOracleEngine`), escondendo LiveKit/WebRTC.
   - Código nativo **apenas para as lacunas** que `flutter_webrtc` não cobre (seção 6.1): hoje, principalmente o áudio do sistema no macOS.
   - Swift (macOS/iOS) e Kotlin (Android) conforme necessário. C++ (Windows e Linux) só se surgir uma lacuna real nessas plataformas: Swift/Kotlin não as cobrem.
5. **KODevUI permanece agnóstico de mídia.** Componentes visuais (tile de vídeo, grid, picker de fontes, seletor de qualidade) recebem dados/widgets; não dependem de WebRTC.
6. **Backend de controle próprio e pequeno** (salas, convites, usuários, emissão de tokens JWT do LiveKit). LiveKit cuida de sinalização de mídia.
7. **Reavaliar na Fase 3** a migração para um núcleo nativo compartilhado (Rust/C++ via `dart:ffi`) se as limitações do `flutter_webrtc` virarem gargalo (seção 3, opção D).

---

## 3. Opções consideradas

### Opção A — Engine 100% próprio por plataforma (proposta original levada ao limite)

Captura + encode + transporte próprio (RTP/UDP ou QUIC) escritos em Swift, Kotlin, C++ para cada plataforma, mais servidor de relay próprio.

| Dimensão | Avaliação |
|---|---|
| Complexidade | Muito alta. Reimplementar congestion control (GCC/TWCC), NACK/RTX, FEC, jitter buffer, ICE/STUN/TURN, DTLS-SRTP, sincronia A/V — 5 vezes (uma por plataforma) |
| Custo | 12–24+ meses para paridade mínima com WebRTC, com um time experiente em mídia |
| Escalabilidade | Depende 100% do que for construído |
| Familiaridade | Baixa: é um domínio especializado (engenheiros de mídia em tempo real) |

**Prós:** controle total; sem dependências pesadas; aprendizado profundo.
**Contras:** a parte difícil (rede ruim, Wi-Fi, 4G, NAT simétrico, firewall corporativo) é exatamente a que o WebRTC levou 10+ anos para acertar. Cinco implementações divergentes do mesmo protocolo = cinco conjuntos de bugs. Não interopera com browser (perde viewer web grátis).

### Opção B — `flutter_webrtc` puro + SFU próprio/mediasoup

Usar `flutter_webrtc` direto, escrever a sinalização e um SFU com mediasoup (Node/C++) ou Pion (Go).

| Dimensão | Avaliação |
|---|---|
| Complexidade | Média-alta (sinalização, gestão de rooms, simulcast, reconexão por conta própria) |
| Custo | 4–6 meses para MVP sólido |
| Escalabilidade | Boa, mas multi-nó/multi-região é trabalho próprio |
| Familiaridade | Média |

**Prós:** controle de servidor; sem acoplamento a SDK de terceiros no cliente.
**Contras:** reescreve o que LiveKit já entrega (rooms, reconexão, simulcast, adaptive stream, dynacast, TURN embutido, egress).

### Opção C — LiveKit (server self-hosted + `livekit_client`) + KOracleEngine fino *(escolhida)*

| Dimensão | Avaliação |
|---|---|
| Complexidade | Baixa-média. Complexidade concentrada nas lacunas de plataforma |
| Custo | MVP desktop + viewer web em ~2–3 meses solo; iOS/Android +1–2 meses cada |
| Escalabilidade | Multi-nó com Redis; multi-região com roteamento por região; testado em produção por terceiros |
| Familiaridade | Alta para quem já faz Flutter: API Dart de alto nível |

**Prós:** simulcast/SVC, adaptive stream (viewer recebe a resolução do tamanho do tile), dynacast (para encoders sem viewers), reconexão, TURN/TLS embutido, E2EE pronto, egress (gravação/RTMP/HLS), load tester. Cliente web compatível. LiveKit Cloud existe como plano B se infra própria virar fardo.
**Contras:** acoplamento ao modelo de room do LiveKit; `flutter_webrtc` tem lacunas em desktop (áudio do sistema, picker, Wayland); versões de libwebrtc ditadas pelo `flutter_webrtc` (WebRTC-SDK); customizações profundas de encoder ficam difíceis.

### Opção D — Núcleo nativo compartilhado (Rust ou C++ com libwebrtc) via `dart:ffi`

Um único core (ex.: LiveKit Rust SDK `livekit/rust-sdks`, ou libwebrtc C++ direto) compilado para cada plataforma, exposto ao Dart por FFI (`flutter_rust_bridge` ou `ffigen`). Módulos de captura nativos por plataforma alimentam o core. É a arquitetura mais parecida com a do Discord.

| Dimensão | Avaliação |
|---|---|
| Complexidade | Alta (build cross-platform de libwebrtc/Rust, FFI, texturas) |
| Custo | 6–10 meses até superar a Opção C em qualidade |
| Escalabilidade | Igual à C no servidor; melhor no cliente (controle de encoder, captura zero-copy) |
| Familiaridade | Baixa-média (Rust/C++, toolchains de cada SO) |

**Prós:** um único núcleo de mídia testado uma vez; captura zero-copy (IOSurface/D3D11 texture direto no encoder); controle total de encoder, content hints, áudio; independência do roadmap do `flutter_webrtc`.
**Contras:** custo de build e manutenção alto; texturas de vídeo para Flutter continuam por plataforma.

## 4. Análise de trade-offs

- **Onde a proposta original está certa:** captura de tela *é* intrinsecamente nativa e diferente em cada SO. Código Swift/Kotlin/C++ vai existir de qualquer jeito.
- **Onde ela está errada:** encode e transporte não devem ser por plataforma. A qualidade percebida de um screen share (stream que não congela no Wi-Fi do vizinho) vem de congestion control, retransmissão e adaptação — e isso é o WebRTC. Reimplementar é o maior risco técnico possível do projeto.
- **C antes de D:** C entrega produto validável rápido; o código de captura nativo escrito para preencher lacunas em C é reaproveitável em D. A fachada Dart do KOracleEngine é o que permite trocar C por D sem mexer no app.
- **SFU vs P2P vs MCU:** P2P mesh exige que o streamer faça upload de uma cópia por viewer (6 Mbps × 5 viewers = 30 Mbps de upload — inviável). MCU decodifica e re-encoda no servidor (caro e adiciona latência). SFU só repassa pacotes: o streamer sobe uma vez (ou 2–3 camadas de simulcast) e o servidor distribui.

---

## 5. Arquitetura proposta

### 5.1 Visão geral

```
                         ┌──────────────────────────── Control plane ───────────────────────────┐
                         │                                                                       │
 ┌──────────────┐  HTTPS │  ┌───────────────┐    ┌────────────┐    ┌──────────┐                  │
 │ KOracle app  │───────────▶│ KOracle API   │───▶│ PostgreSQL │    │  Redis   │◀──────┐          │
 │ (Flutter)    │  WSS   │  │ (auth, salas, │    └────────────┘    └──────────┘       │          │
 │              │───────────▶│ convites,     │──────────────────────────▲              │          │
 │ ┌──────────┐ │        │  │ tokens JWT,   │      webhooks LiveKit    │              │          │
 │ │ KODevUI  │ │        │  │ presença)     │◀─────────────────────────┤              │          │
 │ └──────────┘ │        │  └───────────────┘                          │              │          │
 │ ┌──────────┐ │        └─────────────────────────────────────────────┼──────────────┼──────────┘
 │ │ KOracle  │ │                                                      │              │
 │ │ Engine   │ │   WSS (sinalização LiveKit)   ┌───────────────────────┴──────┐       │
 │ │  ├ livekit_client ───────────────────────▶│ LiveKit SFU (região A)        │◀──────┘ (estado multi-nó)
 │ │  ├ flutter_webrtc │◀═══ UDP/SRTP ════════▶│  + TURN/TLS 443 embutido       │
 │ │  └ nativo │ │        (ou TCP/TLS fallback) └──────────────────────────────┘
 │ └──────────┘ │                                ┌──────────────────────────────┐
 └──────────────┘                                │ LiveKit SFU (região B) ...    │
                                                 └──────────────────────────────┘
 Opcional: LiveKit Egress (gravação, RTMP, HLS) · coturn dedicado · Prometheus/Grafana
```

### 5.2 Fluxo de uma transmissão

1. Usuário abre sala no app → `POST /rooms/{id}/join` na KOracle API.
2. API valida permissão e devolve `{livekitUrl, token}` (JWT assinado com API key/secret do LiveKit, com grants `roomJoin`, `canPublish`, `canSubscribe`, TTL curto).
3. App conecta ao SFU via `livekit_client` (WebSocket de sinalização + ICE).
4. Streamer abre o picker → KOracleEngine lista fontes (`desktopCapturer.getSources` no desktop; extensão de broadcast no iOS; `MediaProjection` no Android).
5. Engine cria track de vídeo da fonte (content hint `detail`/`text` para documentos, `motion` para jogos) e track de áudio do sistema (nativo).
6. Publica com simulcast (ex.: 1080p60 / 540p30 / 270p15) ou SVC (VP9/AV1 L3T3).
7. Viewers veem o stream como "ao vivo" (metadado da track + thumbnail) mas só assinam ao clicar. LiveKit adaptive stream escolhe a camada pelo tamanho do widget.
8. Webhooks do LiveKit (`participant_joined`, `track_published`, `room_finished`) atualizam presença/estado na API e são retransmitidos aos clientes pelo WebSocket da API.

### 5.3 Fronteiras de cada repositório

```
KOracle (app)
 ├─ lib/
 │   ├─ features/auth, rooms, stream (player, picker, controles), settings
 │   ├─ data/ (cliente HTTP/WS da KOracle API)
 │   └─ main.dart
 ├─ ios/KOracleBroadcast/          ← Broadcast Upload Extension (target do APP, não do plugin)
 ├─ macos/Runner/*.entitlements    ← permissões (rede, câmera/mic se houver)
 └─ depende de: kodev_ui, koracle_engine

KOracleEngine (plugin)
 ├─ lib/ API pública: KOracleEngine, ShareSource, ShareQuality, StreamView, eventos (Stream<...>)
 │   └─ internamente usa livekit_client; nunca exporta tipos do LiveKit
 ├─ darwin/ Swift: áudio do sistema (ScreenCaptureKit), SCContentSharingPicker, helpers da extensão iOS
 ├─ android/ Kotlin: foreground service mediaProjection, AudioPlaybackCapture
 ├─ windows/ C++: WASAPI process loopback, Windows.Graphics.Capture se necessário
 ├─ linux/ C++: PipeWire/portal (fase posterior)
 └─ pigeons/ definição Pigeon da API nativa (tipada, gera Dart/Swift/Kotlin/C++)

KODevUI (package)
 └─ componentes genéricos: KOVideoTile(child: Widget), KOStreamGrid, KOSourcePickerGrid,
    KOQualitySelector, KOLiveBadge, KOViewerCount, tokens de tema
    (sem dependência de WebRTC — o app injeta o widget de vídeo como child)

KOracleServer (novo repositório)
 └─ API de controle + infra (docker compose / IaC: livekit, redis, postgres, caddy)
```

Regras de dependência: `KOracle → KOracleEngine`, `KOracle → KODevUI`. **KOracleEngine e KODevUI não se conhecem.**

### 5.4 Comunicação Dart ↔ nativo

| Caminho | Uso | Tecnologia |
|---|---|---|
| Controle (iniciar/parar, listar fontes, permissões, eventos) | Baixa frequência | **Pigeon** (substitui o MethodChannel do scaffold; tipos gerados para Dart/Swift/Kotlin/C++) |
| Eventos contínuos (estado de captura, níveis de áudio) | Média frequência | EventChannel / Pigeon event channels |
| Frames de vídeo | 60×/s, MBs por frame | **Nunca** por canal. Ficam no nativo: captura → encoder → rede; decode → textura (`TextureRegistry`) |
| Hot paths futuros (Opção D) | Altíssima frequência | `dart:ffi` |

Render de vídeo no Flutter: `Texture(textureId)` — `CVPixelBuffer` via `FlutterTexture` no Darwin, `SurfaceProducer` no Android, pixel buffer ou superfície GPU (DXGI shared handle) no Windows, `FlTextureGL`/pixel buffer no Linux. No Windows e Linux, cópias de pixel buffer em 1080p60/4K custam CPU — medir cedo.

---

## 6. Detalhamento técnico

### 6.1 Captura por plataforma

| Plataforma | Vídeo | Áudio do sistema/app | Restrições e armadilhas | Linguagem |
|---|---|---|---|---|
| **macOS** | ScreenCaptureKit (12.3+). `SCContentSharingPicker` (14+) dá picker do sistema e evita pedir permissão global | ScreenCaptureKit captura áudio (13+), com `excludesCurrentProcessAudio` para não capturar o próprio KOracle (evita eco do áudio dos outros streams) | Permissão "Gravação de Tela" (TCC); o macOS 15+ volta a pedir confirmação periodicamente para apps que usam a API sem o picker; app precisa reiniciar após conceder em versões antigas. Elevar mínimo do plugin para macOS 13 (scaffold está em 12.0) | Swift |
| **iOS/iPadOS** | ReplayKit **Broadcast Upload Extension** (tela inteira do sistema). `RPScreenRecorder` só captura o próprio app | ReplayKit entrega áudio do app + mic | A extensão é **outro processo** com limite de memória baixo (~50 MB): não dá para rodar Flutter nela. Dois desenhos: (a) extensão envia frames por socket Unix/App Group ao app principal, que publica (o `flutter_webrtc` já suporta esse modelo); (b) extensão roda o WebRTC e publica sozinha. Sem escolha de janela. O app principal precisa estar vivo em background (modo de áudio/VoIP) no desenho (a) | Swift |
| **Android** | `MediaProjection` → `VirtualDisplay` → `Surface` do encoder | `AudioPlaybackCaptureConfiguration` (10+); só captura apps que permitem (`allowAudioPlaybackCapture`), nunca chamadas | Foreground service com `foregroundServiceType="mediaProjection"` e permissão `FOREGROUND_SERVICE_MEDIA_PROJECTION` (14+); consentimento por sessão e token não reutilizável (14+); compartilhamento de app único (14 QPR2+); o sistema oculta conteúdo sensível (notificações de OTP) durante o share (15+); fabricantes (Xiaomi, Samsung) matam serviços agressivamente | Kotlin |
| **Windows** | Windows.Graphics.Capture (WGC, Win10 1903+ para janela/monitor). DXGI Desktop Duplication como fallback/monitor inteiro | WASAPI loopback; **process loopback** (build 20348+) permite incluir só a árvore de processo do app compartilhado ou excluir o KOracle — é o que dá "áudio só do jogo" | Borda amarela do WGC (removível no Win11 via `IsBorderRequired`); conteúdo DRM aparece preto; janelas minimizadas não renderizam. GPUs híbridas (notebook) podem exigir cópia entre adaptadores | C++ (C++/WinRT) |
| **Linux** | Wayland: `xdg-desktop-portal` ScreenCast + PipeWire (picker é do portal, não customizável). X11: XComposite/XShm | PipeWire/PulseAudio monitor source | Fragmentação de compositores (GNOME, KDE, wlroots); empacotar como Flatpak. Sugestão: última plataforma | C/C++ |
| **Web** | `getDisplayMedia` | Áudio de aba/sistema só em Chromium e parcial | Recomendo **apenas viewer** na web: link de convite abre no browser sem instalar nada | Dart (via `flutter_webrtc` web) |

**O que o `flutter_webrtc` já cobre** (leitura do código na branch `main`, com changelog em 1.6.3, em 2026-11-06; nada disto foi executado ainda):

| Item | Estado |
|---|---|
| Vídeo no macOS | ScreenCaptureKit, com fallback para o capturer antigo |
| Áudio no Windows | `ApplicationLoopbackCapturer` (WASAPI), ligado à constraint `audio` do `getDisplayMedia`. Por padrão captura todo o sistema excluindo o próprio processo |
| Áudio no Linux | `pulse_loopback_capturer` existe no repositório |
| iOS | `FlutterBroadcastScreenCapturer` (socket entre a extensão e o app) |
| Swift Package Manager | `Package.swift` em iOS e macOS, expondo `WebRTC` para plugins dependentes |

**Lacunas que justificam código nativo no KOracleEngine:**

1. **Áudio do sistema no macOS.** O capturer registra só `SCStreamOutputTypeScreen`. É o único item nativo da Fase 0.
2. Picker nativo do macOS 14+ (`SCContentSharingPicker`), a confirmar.
3. Wayland no Linux, a confirmar.
4. Controle fino do encoder (bitrate máximo por preset, content hint, `degradationPreference`), a confirmar.
5. Integrações de SO: bandeja/menu bar, atalhos globais, impedir sleep durante a transmissão, ocultar o próprio app da captura.

**Pontos a verificar:**

- `ScreenShareCaptureOptions.captureScreenAudio` do `livekit_client` é documentado como "browser only". No desktop pode ser necessário chamar o `getDisplayMedia` do `flutter_webrtc` direto e publicar a track pelo LiveKit.
- Build mínimo do process loopback: o código do `flutter_webrtc` indica 19041, e a tabela acima cita 20348.

Injetar uma fonte nativa customizada (ex.: áudio) num track do `flutter_webrtc` exige que o plugin linke o mesmo binário de libwebrtc que ele usa (pod `WebRTC-SDK` / artefato Android do webrtc-sdk). Isso é um acoplamento de versão: fixar versões e cobrir com teste de integração.

### 6.2 Codecs e qualidade

| Codec | Encode HW | Uso recomendado |
|---|---|---|
| **H.264** | Universal (VideoToolbox, MediaCodec, NVENC/AMF/QuickSync via Media Foundation) | Padrão/fallback. Compatível com tudo |
| **VP9** | Parcial | SVC (L1T3/L3T3) bom para screen content; encode em software custa CPU |
| **AV1** | NVIDIA RTX 40+, AMD RDNA3+, Intel Arc/Meteor Lake+; Apple só decode (M3/A17 Pro+) | Melhor compressão e ferramentas de screen content; usar quando ambos os lados suportam |
| H.265 | Forte em Apple | Suporte em WebRTC recente e desigual; questões de licença. Não priorizar |

Presets sugeridos (H.264, ponto de partida para tuning):

| Preset | Resolução/FPS | Bitrate alvo | Content hint | Degradação |
|---|---|---|---|---|
| Texto/código | 1080p @ 15–30 | 2–3 Mbps | `text` | manter resolução |
| Padrão | 1080p @ 30 | 3–4 Mbps | `detail` | balanceado |
| Jogo | 1080p @ 60 | 6–8 Mbps | `motion` | manter framerate |
| Fonte | 1440p/4K @ 60 | 12–25 Mbps | `motion` | manter framerate |

Simulcast: publicar 2–3 camadas para que viewers com rede ruim ou tile pequeno recebam camada menor, sem o streamer re-encodar por viewer.

### 6.3 Rede

- **ICE/STUN/TURN:** ~10–20% dos usuários não conectam via UDP direto (NAT simétrico, firewall corporativo). TURN sobre **TLS na porta 443** é obrigatório. LiveKit tem TURN embutido; coturn dedicado se precisar escalar separado.
- **Portas do SFU:** faixa UDP (ex.: 50000–60000) ou porta única UDP multiplexada; TCP fallback.
- **Regiões:** latência é física. Começar com uma região (ex.: São Paulo) e adicionar conforme a base de usuários.
- **Proteção:** SFU expõe UDP público — rate limiting, tokens de curta duração, provedor com mitigação de DDoS.

### 6.4 Backend de controle (KOracleServer)

Escopo pequeno de propósito:

| Componente | Responsabilidade | Sugestão |
|---|---|---|
| Auth | Login (OAuth Google/Apple/GitHub ou magic link), sessões | Provedor gerenciado no começo (ex.: Supabase Auth, Firebase Auth) ou JWT próprio |
| Salas/Convites | CRUD de salas, links de convite com expiração, papéis (dono/moderador/viewer) | PostgreSQL |
| Token de mídia | Emitir JWT do LiveKit com grants mínimos | É só um JWT HS256 — implementável em qualquer linguagem |
| Presença/eventos | Quem está online, quem está ao vivo, thumbnails | WebSocket + Redis pub/sub; consumir webhooks do LiveKit |
| Thumbnails de streams | Preview "ao vivo" no lobby | Cliente envia um JPEG pequeno a cada ~10–30 s para storage (S3/R2) |

Linguagem: **Dart** (ex.: Dart Frog, Serverpod, Relic/Shelf) é viável e permite compartilhar modelos com o app; **Go** é a alternativa natural se quiser ficar próximo do ecossistema LiveKit (server SDK oficial). O control plane não é gargalo de performance; escolher pela produtividade.

### 6.5 Escala e custo

Banda é o custo dominante. Conta por viewer:

```
1080p60 a 6 Mbps → 6 Mb/s × 3600 s ÷ 8 = 2,7 GB por viewer-hora
1 streamer + 10 viewers por 1 h ≈ 27 GB de egress
```

| Provedor | Egress | Custo dessa sessão de 1 h |
|---|---|---|
| AWS/GCP (preço de lista ~US$ 0,08/GB) | Cobrado por GB | ~US$ 2,16 |
| Bare metal/VPS com tráfego incluso (Hetzner, OVH etc.) | Porta de 1 Gbps com franquia generosa | Fixo mensal |
| LiveKit Cloud | Por minuto de participante + banda | Ver tabela atual; bom para começar sem operar infra |

Conclusão: **não hospedar SFU em hyperscaler com egress por GB.** Bare metal com tráfego incluso é a escolha econômica.

Capacidade aproximada: um SFU repassa pacotes sem decodificar; o limite costuma ser a placa de rede antes da CPU. 1 Gbps ≈ 150 viewers de 1080p60 a 6 Mbps.

Para audiências grandes (centenas/milhares): SFU em cascata entre nós, ou modelo híbrido — os primeiros N viewers em WebRTC e o resto via LiveKit Egress → LL-HLS em CDN (latência 2–5 s). Media over QUIC (MoQ) é uma alternativa emergente para baixa latência em escala; acompanhar, não adotar no MVP.

### 6.6 Segurança e privacidade

- DTLS-SRTP sempre (padrão WebRTC): o tráfego é criptografado em trânsito, mas o SFU tem acesso à mídia em claro.
- **E2EE (fase posterior):** LiveKit suporta E2EE com Insertable Streams/SFrame e chave compartilhada; troca de chaves robusta (MLS, como o DAVE do Discord) é trabalho adicional. E2EE desabilita recursos que precisam ver a mídia (gravação no servidor).
- Tokens de mídia com TTL curto e grants mínimos (viewer sem `canPublish`).
- Indicador permanente de "você está transmitindo" + atalho global de parar.
- Excluir o próprio KOracle da captura (evita efeito espelho e vazamento de chat/notificações).
- iOS: `PrivacyInfo.xcprivacy` no plugin (o `Package.swift` já tem o lugar comentado).
- Moderação: denúncia, ban, kick, limite de criação de salas por conta (abuso de banda é custo direto).

### 6.7 Distribuição

| Plataforma | Requisitos |
|---|---|
| macOS | Developer ID + notarização (fora da App Store) ou App Store com sandbox (ScreenCaptureKit funciona no sandbox). Atualização automática: Sparkle |
| Windows | Assinatura de código (certificado com reputação no SmartScreen), instalador MSIX ou Inno Setup/Squirrel, auto-update |
| Linux | Flatpak (portal é necessário de qualquer forma), AppImage opcional |
| iOS | App + Broadcast Extension no mesmo App Group; revisão da App Store explica o uso da extensão |
| Android | Declarar foreground service type na Play Console (formulário de justificativa para `mediaProjection`) |

Dependências Apple: o plugin e o `flutter_webrtc` têm `Package.swift`, mas o build atual do `example/` no macOS passa por CocoaPods. O trunk do CocoaPods entra em modo somente leitura e o Flutter está migrando para SPM, então isso precisa ser revisto.

### 6.8 Recursos de desktop que Flutter não resolve sozinho

- **Pop-out do stream em janela separada:** suporte multi-janela no Flutter desktop ainda é recente; validar o estado atual ou usar plugin de multi-window.
- Bandeja do sistema / menu bar, atalhos globais, "manter acordado": plugins existentes ou código nativo no KOracleEngine.
- Overlay sobre jogos: fora do escopo (exige injeção/hook, como o overlay do Discord).

### 6.9 Observabilidade e testes

- Coletar `getStats()` periodicamente (bitrate, FPS enviado/recebido, perda, RTT, jitter, `qualityLimitationReason`, freezes) e enviar ao backend. É o único jeito de saber se a experiência está boa.
- LiveKit expõe métricas Prometheus; Grafana para dashboards.
- Testar em rede degradada: Network Link Conditioner (macOS/iOS), `tc netem` (Linux), clumsy (Windows). Cenários: 3% de perda, 200 ms de RTT, banda limitada a 2 Mbps.
- Carga do SFU: `lk load-test` (CLI do LiveKit).
- Testes de integração do plugin no `example/` com o app real conectando a um LiveKit local (`livekit-server --dev`).
- Soak test: transmissão de 4 h para pegar vazamento de memória (frames/texturas) — o bug mais comum em apps de vídeo.

---

## 7. Consequências

**Fica mais fácil:**
- Entregar um MVP funcional em meses, não anos.
- Viewer pela web sem instalar nada.
- Escalar horizontalmente o SFU e adicionar regiões.
- Trocar a implementação interna do engine (C → D) sem mexer no app, graças à fachada do KOracleEngine.

**Fica mais difícil:**
- Customização profunda do pipeline de mídia enquanto depender do `flutter_webrtc`.
- Controlar versão de libwebrtc (vem do `flutter_webrtc`).
- Operar infra de UDP em tempo real (SFU, TURN, DDoS) — é infraestrutura de produção de verdade.

**A revisitar:**
- Fase 3: migrar para núcleo compartilhado (Rust/C++ + FFI) se lacunas do `flutter_webrtc` dominarem o roadmap.
- E2EE com troca de chaves MLS.
- Estratégia para audiências > 100 viewers por stream.
- Suporte a Linux/Wayland.

## 8. Riscos

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Áudio do sistema no macOS: injetar ScreenCaptureKit numa track WebRTC | Alta | Alto | Prova de conceito na Fase 0 antes de qualquer UI. No Windows, validar a implementação que o `flutter_webrtc` já traz |
| iOS Broadcast Extension: limite de memória, IPC, app em background | Alta | Médio | Usar o modelo já suportado pelo `flutter_webrtc`; adiar iOS como streamer (iOS como viewer é trivial) |
| Custo de banda | Média | Alto | Bare metal, opt-in para assistir, adaptive stream, limites por plano |
| Acoplamento de versão libwebrtc no código nativo do plugin | Média | Médio | Fixar versões, testes de integração no `example/` |
| Render de texturas lento no Windows/Linux em 1080p60+ | Média | Médio | Medir na Fase 0; caminhos GPU (DXGI shared handle) |
| Mudanças de política de SO (Android a cada versão, TCC no macOS) | Alta | Médio | Acompanhar betas; isolar código nativo por versão de SO |
| Escopo crescer para "Discord inteiro" (chat, voz, servidores) | Alta | Alto | Manter "só compartilhamento de tela" como norte; voz é barato com WebRTC, chat não |

## 9. Plano de ação

**Fase 0 — Prova técnica (2–4 semanas)**
1. [ ] Subir `livekit-server --dev` local.
2. [ ] No `example/` do KOracleEngine: publicar tela no macOS e assistir em outro dispositivo/browser com `livekit_client`.
3. [ ] Medir: latência glass-to-glass (cronômetro na tela), CPU do streamer, FPS real em 1080p60.
4. [ ] Provar áudio do sistema no macOS: ScreenCaptureKit injetado no track WebRTC, em Swift no KOracleEngine — **é o maior risco técnico**.
4b. [ ] Validar no Windows a captura e o loopback que o `flutter_webrtc` já traz (sem código nativo nosso, a menos que falhe). Roda na máquina Windows do autor, com o servidor no Mac acessível pela LAN.
5. [ ] Elevar mínimos: macOS 13 no `Package.swift`; trocar o MethodChannel do scaffold por Pigeon.

**Resultados parciais da Fase 0 (macOS, 2026-11-06)**

Medido com transmissor, viewer e servidor na mesma máquina, build profile e movimento sintético:

- Vídeo de tela inteira funciona, com latência de 63–95 ms e encode/decode por hardware.
- Sob movimento, o FPS ficou em 28–34 em vez de 60, com `qualityLimitationReason: none`. A causa não foi identificada.
- O preset não limita a resolução: saiu a nativa (2056x1328). O upload real foi de 7,5 Mbps, somando as duas camadas.
- Áudio do sistema funciona pela opção de nó no `AVAudioEngine` do ADM, com ScreenCaptureKit como fonte e modo manual, sem pedir microfone. Ainda não foi verificado se a reprodução fica muda em quem transmite.
- A track de áudio precisa ser criada no nativo, porque o `getUserMedia` do `flutter_webrtc` sempre pede acesso ao microfone (e derruba o app sem `NSMicrophoneUsageDescription`).
- Com assinatura ad-hoc, cada rebuild invalida a permissão de Gravação de Tela. Assinar com certificado de desenvolvimento resolve: a permissão sobreviveu aos rebuilds seguintes.

**Fase 1 — MVP desktop + viewer web (6–10 semanas)**
6. [ ] KOracleServer: auth, salas, convites, emissão de tokens, webhooks.
7. [ ] KOracleEngine: fachada (`listSources`, `startShare`, `stopShare`, `join`, `leave`, `StreamView`, eventos de qualidade).
8. [ ] KODevUI: tile de vídeo, grid, picker de fontes com thumbnails, seletor de qualidade, badges.
9. [ ] KOracle: fluxo sala → picker → transmitir → assistir; opt-in de viewer; reconexão.
10. [ ] Deploy de um SFU em bare metal com TURN/TLS 443; métricas de `getStats()`.

**Fase 2 — Mobile (6–10 semanas)**
11. [ ] Android streamer (MediaProjection + foreground service + AudioPlaybackCapture).
12. [ ] iOS streamer (Broadcast Upload Extension + App Group).
13. [ ] Viewers mobile (já funcionam desde a Fase 1, só polir UX).

**Fase 3 — Maturidade**
14. [ ] Codecs avançados (AV1/VP9 SVC quando suportado), presets por tipo de conteúdo.
15. [ ] E2EE.
16. [ ] Linux (PipeWire/portal).
17. [ ] Reavaliar Opção D (núcleo compartilhado via FFI) com dados reais das Fases 0–2.
