# 대상 기계 하드웨어

OPENSTEP 4.2가 도는 개발·검증 기계의 구성. 전부 `pcils` 실측
(2026-07-20). 원본 출력은 [../pcils/scan-nextonion.txt](../pcils/scan-nextonion.txt).

## 요약

Fujitsu 보드, **Intel 865G(Springdale) + ICH5** 칩셋. OPENSTEP이 도는
기계치고는 상당히 최신 세대다.

| 위치 | 장치 | 비고 |
|------|------|------|
| 00:00.0 | Intel 82865G/PE/P Host Bridge `[8086:2570]` | |
| 00:02.0 | Intel 82865G 내장 그래픽 `[8086:2572]` | 미사용(Matrox 사용) |
| 00:03.0 | Intel PCI-to-CSA Bridge `[8086:2573]` | → 하위 버스 **02** |
| 00:1e.0 | Intel 82801 PCI Bridge `[8086:244e]` | → 하위 버스 03~04 |
| 00:1f.0 | ICH5 LPC Interface `[8086:24d0]` | |
| 00:1f.1 | ICH5 IDE Controller `[8086:24db]` | |
| 00:1f.3 | ICH5 SMBus `[8086:24d3]` | |
| **02:01.0** | **Intel 82547EI Gigabit Ethernet `[8086:1019]`** | **Pro1000 대상** |
| 03:0b.0 | DEC 21041 Tulip 10Mb `[1011:0014]` | **현재 en0** |
| 03:0d.0 | HiNT HB4 PCI-to-PCI Bridge `[3388:0021]` | → 하위 버스 04 |
| 04:00.0 | Matrox MGA G400/G450 `[102b:0525]` | 콘솔 디스플레이 |

## 네트워크 인터페이스 — 헷갈리기 쉬운 부분

이 기계의 이더넷 컨트롤러는 **딱 둘**이다.

### 02:01.0 — Intel 82547EI 기가비트 (드라이버 개발 대상)

```
IRQ 3, pin A
BAR0: mem 0xe8100000 (32-bit, non-prefetchable)   ← 레지스터 공간
BAR2: io  0x2000
Subsystem: [10cf:11bc] Fujitsu
```

- 온보드. **CSA(Communication Streaming Architecture)** 포트로 칩셋에
  직결되어 `00:03.0` 브리지 하위의 버스 02에 나타난다.
- CSA지만 SDM이 명시한다 — *"Logically, it still follows PCI
  configuration."* config space·BAR·IRQ 할당이 전부 정상이라
  DriverKit의 PCI 자동감지가 그대로 통한다.
- **자작 `Pro1000` 드라이버가 잡고 있다** — `en1`, 부팅 시 자동 로드.
  실측 172(송신)/248(수신) Mbit/s — tulip 대비 약 21배.

### 03:0b.0 — DEC 21041 Tulip 10Mb (현재 en0, 원격 접속 생명줄)

```
IRQ 9, pin A
BAR0: io  0x3000
en0: Ethernet address 00:00:c5:0c:30:5a
```

- OPENSTEP 기본 제공 `DECchip21041` 드라이버가 잡고 있다.
- **Intel 제품이 아니다** — DEC(현 Intel이 인수한 계열이지만 벤더 ID는
  `0x1011`) Tulip 칩이다. Intel PRO/100과 혼동하기 쉬우나 별개다.
- 모든 telnet·NFS·gcds 트래픽이 이 카드를 지난다. **드라이버 실험 중
  절대 건드리지 말 것** — 이게 끊기면 원격 복구 수단이 없다.

### tulip 제거 계획

82547EI가 온보드이므로 드라이버가 완성되면 tulip(en0)을 제거할
예정이다.

**선결 조건은 en1을 NetInfo에 등록하는 것이다.** 지금 부팅 시 en1이
주소 없이 올라와 엉터리 기본 경로가 생기는 건 NIC이 둘이어서가 아니라
en1이 NetInfo에 없기 때문이다(`tools/nx-fixroute.sh` 참조). 등록하지
않은 채 en0만 빼면 **기계에 접속할 수단이 사라진다.**

> **그 시점에 위험의 성격이 바뀐다.** 지금은 en0가 살아 있어 en1을
> 마음껏 깨뜨려도 원격 접속이 유지된다 — 이번 개발에서 머신을 여러 번
> 멈춰 세우고도 복구할 수 있었던 것이 그 덕이다. tulip을 빼면 **이
> 드라이버가 유일한 접속 경로**가 된다.

### Intel PRO/100(8255x)은 현재 버스에 없다

스캔 결과 8255x 계열 장치는 발견되지 않았다. 스캔은 완전하다:
사용 중인 버스(0·2·3·4)가 모두 스캔 범위(0~7) 안이고, 커널이 보고한
장치 수 11과 해석된 수 11이 일치한다. 미장착이거나 슬롯 접촉 불량,
또는 BIOS 비활성으로 보인다.

만약 나중에 장착되더라도 **8255x는 8254x와 완전히 다른 MAC**(CU/RU
커맨드 유닛 구조)이므로 Pro1000 드라이버의 대상이 아니며, 별도
드라이버가 필요하다. `pcils`의 이름표가 둘을 명시적으로 구분한다.

## 드라이버 개발에 영향을 주는 82547EI 특성

Intel SDM(`ref/8254x-sdm.pdf`, 표지에 82547xx 명시) 기준.

| 특성 | 영향 |
|------|------|
| CSA 포트 연결 | 논리적으로는 PCI — DriverKit PCI 매칭 유효 |
| **64비트 주소 미지원** | 32비트 DMA만 쓰면 됨 (오히려 단순화) |
| 패킷 FIFO 40KB (타 8254x는 64KB) | Tx 링/임계값 설정에 영향 |
| Tx FIFO stall 에라타 | 512MB 부하에서도 미발생 → **워크어라운드 넣지 않음** |
| 내장 PHY가 clause 40 autoneg 자체 수행 (§8.5) | **실측 확인** — `CTRL.SLU\|ASDE`만으로 1.3초 만에 1000Mb/s. MDIC PHY 초기화 불필요 |
| BIOS의 특수 인터럽트 구성 필요 | BIOS는 IRQ 3을 배정했다(스캔 확인). 다만 그것만으로는 DriverKit에 전달되지 않는다 — `Instance0.table`의 `"IRQ Levels"`가 **부팅 포함 모든 경로에서** 필수 |

## `netstat -i`의 "10MB Ethernet"은 속도가 아니다

모든 이더넷 인터페이스가 이 문자열을 낸다 — 실제로 10Mb인 en0도,
1000Mb/s로 붙은 en1도 같다. `bsd/net/etherdefs.h`의 상수다:

```c
#define IFTYPE_ETHERNET "10MB Ethernet"
```

**바꾸면 안 된다.** 속도 라벨이 아니라 **매체 종류 식별자**이고, 상위
프로토콜 핸들러가 이것을 `strcmp`로 비교해 이더넷 여부를 판정한다
(NextDev *Writing Loadable Kernel Servers* 8장의 예제):

```c
if (strcmp(if_type(rifp), IFTYPE_ETHERNET) != 0)
        return;          /* 이더넷이 아니면 붙지 않는다 */
```

문자열을 바꾸면 IP 핸들러가 그 인터페이스에 붙지 않는다. 부팅 로그의

```
IP protocol enabled for interface en1, type "10MB Ethernet"
```

는 드라이버가 아니라 **그 핸들러가 찍는 성공 메시지**다 — 저 줄이
보인다는 것 자체가 타입 검사를 통과했다는 뜻이다.

협상된 실제 속도는 드라이버가 따로 남긴다:
`Pro1000: after init: link UP, 1000Mb/s, full duplex`.

## 하드웨어 다시 확인하는 법

```sh
./tools/nx.sh '/tmp/pcils'                 # 요약
./tools/nx.sh '/tmp/pcils -v'              # config 헤더 hex 포함
./tools/nx.sh '/tmp/pcils -o /ndrv/openstep-intel1000/pcils/scan-nextonion.txt'
```

설치·빌드 방법은 [../pcils/README.md](../pcils/README.md).
