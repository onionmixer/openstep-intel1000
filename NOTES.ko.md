# pro1000 — Intel 82547EI 기가비트 이더넷 드라이버

**현재: 1.0.** 로드맵 P1~P6에 더해 에러 계정·링 고갈 복구, 링크 변동
대응, 진단 로그 정리까지 마쳤다. 실기(82547EI) 실측 송신
145~172 Mbit/s(최고 172), 수신 248 Mbit/s.

OPENSTEP 4.2용 DriverKit 드라이버. 대상은 이 기계에 온보드로 달린
**Intel 82547EI `[8086:1019]` @ 02:01.0**. 설계와 로드맵은
[PLAN.md](PLAN.md), 하드웨어 사실은 [doc/hardware.md](doc/hardware.md).

## P1 완료 (2026-07-20)

P1은 하드웨어를 구동하지 않는 **정찰 단계**다. 이후 모든 단계가
의존하는 세 가지를 실기로 확인하는 것이 목적이었다.

### 결과

| 확인 항목 | 결과 |
|-----------|------|
| BAR0 MMIO 매핑 | ✅ `IOMapPhysicalIntoIOTask()` 동작 — phys `0xe8100000` → virt `0x222d8000` (128KB) |
| 레지스터 판독 | ✅ 실제 값 (all-ones/all-zero 아님) |
| **매핑 정확성 교차검증** | ✅ **MAC 주소 `00:16:e6:14:e3:95` (AV 비트 set)** |
| `pcils` 결과와 대조 | ✅ BAR0 `0xe8100000`, IRQ 3 — 정확히 일치 |
| DriverKit `+probe:` 자동 매칭 | ❌ 동적 로드로는 호출되지 않음 (아래 참조) |

실기 로그:

```
Pro1000: standalone scan (arg 0) looking for 8086:1019
Pro1000: found at 02:01.0  BAR0 0xe8100000  IRQ 3
Pro1000: mapped BAR0 phys 0xe8100000 -> virt 0x222d8000 (131072 bytes)
Pro1000: CTRL     0x003c0241
Pro1000: STATUS   0x00000380  link DOWN (cable unplugged?)
Pro1000: EECD     0x0000251a
Pro1000: CTRL_EXT 0x002001c0
Pro1000: MDIC     0x14291a00
Pro1000: RAL0 0x14e61600 RAH0 0x800095e3
Pro1000: MAC address 00:16:e6:14:e3:95 (valid)
```

### 판독 근거

- **MAC 주소가 결정적 증거다.** 하드웨어가 리셋 시 EEPROM에서 수신주소
  0번(RAL0/RAH0)을 채우므로, EEPROM 프로토콜을 건드리지 않고도 카드
  고유 주소를 읽을 수 있다. 첫 바이트 `0x00`은 유니캐스트 + 전역 할당
  OUI를 뜻하고 RAH의 AV 비트가 서 있다. **창이 엉뚱한 물리주소를
  가리켰다면 이렇게 구조화된 값이 나올 수 없다.**
- **link DOWN은 정상이다** — 기가비트 포트에 랜선이 꽂혀 있지 않다.
  오히려 하드웨어의 실제 상태를 읽고 있다는 방증이다(케이블이 연결된
  DEC 21041은 링크 업 상태다). 링크가 내려가 있을 때 duplex/speed
  필드는 의미가 없으므로 출력하지 않는다.

### DriverKit 자동 매칭이 안 걸린 건

`kl_util -l`로 동적 로드하면 `+probe:`가 호출되지 않는다. 하드웨어를
주장하지 않는 `pcils/PCIscan`에서 이미 겪은 것과 같은 현상이며,
**하드웨어가 실재하고 `Auto Detect IDs`가 맞아도 마찬가지**임을 이번에
확인했다. 매칭은 부팅 시 시스템 구성(System.config / Configure.app)에
등록된 드라이버에 대해 일어나는 것으로 보인다.

그래서 이 드라이버는 진입 경로를 두 개 갖는다.

| 경로 | 트리거 | 상태 |
|------|--------|------|
| `+probe:` | DriverKit PCI 매칭 | P1 당시 미동작 → **P6에서 해결**(아래 참조) |
| `pro1000ScanEntry` | `Load_Commands.sect`의 `CALL` | **동작** — config space를 직접 훑어 장치를 찾는다 |

`CALL` 경로가 자립적이라 매칭 없이도 개발을 계속할 수 있다. 부팅
등록은 P6(패키징)에서 다룬다.

## 빌드와 실행

> 이 절은 P1 당시의 손 조작 절차를 대체한 **현재 절차**다. 예전 절차는
> `kl_util -u` 로 언로드하는 단계를 포함했는데, 네트워크 스택에 붙은
> 드라이버에 그걸 하면 **커널이 패닉한다**(아래 "언로드하지 않는다"
> 참조). 지금은 `DETACH` 때문에 언로드가 아예 에러가 되고, 반영은
> 재부팅으로 한다.

```sh
./tools/nx-mount.sh                                    # NFS 마운트
./tools/nx-daemon.sh start                             # gcdsd — 재부팅마다 죽는다
./tools/nx-install-driver.sh openstep-intel1000/Pro1000  # 빌드·설치·크기검증
./tools/nxrun.sh 'grep Pro1000 /usr/adm/messages | tail -15'
```

`/ndrv`가 실패한 soft mount 때문에 `Device busy`로 잠겨 있으면
`MOUNTPT=/ndrv2 ./tools/nx-install-driver.sh ...` 로 우회한다(잠금 자체는
재부팅으로만 풀린다).

**손으로 `cp` 하지 않는다.** 0바이트 번들을 남기면 부팅 때 kern_loader가
무한 루프에 빠진다 — 설치 스크립트의 크기 검증이 그걸 막는다.

**테이블만 고칠 때는 재컴파일이 필요 없다.** 컴파일되는 건
`Pro1000_reloc` 하나뿐이고 `Default.table`·`Instance0.table`은 번들 안의
평문이다. 값을 바꿨으면 다시 설치하고 재부팅하면 된다.

## P2 완료 (2026-07-20)

리셋 → NVM 리로드 확인 → 드라이버 제어로 링크 확립까지 전부 실기 통과.

```
Pro1000: quiesce - masking interrupts, stopping RX/TX
Pro1000: asserting PHY_RST
Pro1000: PHY_RST survived, CTRL 0x803c0241
Pro1000: asserting global RST (no register access for 1200 ms)
Pro1000: global RST survived, CTRL 0x003c0241
Pro1000: station address after reset  00:16:e6:14:e3:95 (valid)
Pro1000: NVM reload OK - address confirmed by two reads
Pro1000: after reset:  link DOWN (STATUS 0x00000380)
Pro1000: SLU+ASDE set, CTRL 0x003c0261 - waiting for link
Pro1000: link came up after 1300 ms
Pro1000: after setup: link UP, 1000Mb/s, full duplex (STATUS 0x00000383)
```

| 확인 항목 | 결과 |
|-----------|------|
| 장치 리셋 (PHY → MAC 순서) | ✅ 통과 |
| NVM 리로드 | ✅ MAC이 리셋 전후 두 독립 판독에서 일치 |
| 드라이버 제어 링크 확립 | ✅ `SLU+ASDE` → **1300ms 만에 1000Mb/s full duplex** |
| **82547에 추가 PHY 초기화가 필요한가** | ✅ **불필요** — 아래 참조 |

### 미결 질문 해소: PHY 초기화 스크립트는 필요 없다

계획서의 열린 질문이었다 — 82547은 82541과 함께 IGP 계열 PHY를 쓰고
Linux/FreeBSD는 이 계열에 `e1000_phy_init_script_82541()`(MDIC 기입
다발)을 돌린다. **실측 결과 기본 링크에는 필요 없다.** 전체 리셋으로
링크가 완전히 내려간 상태에서 `CTRL.SLU|ASDE`만으로 1.3초 만에
1000Mb/s full duplex가 붙었다.

즉 §0의 판단이 최종 확인됐다 — **내장 PHY가 clause 40 auto-negotiation을
스스로 수행하므로 드라이버는 링크를 올리라고 지시하고 결과를 읽기만
하면 된다.** (그 스크립트는 DSP 튜닝·에라타 회피용이며, 링크 품질
문제가 관찰되면 그때 도입한다.)

## P2에서 머신을 두 번 멈춘 일 (2026-07-20)

**반드시 읽을 것.** P2 첫 시도가 **커널을 하드 행**시켰다(ping·telnet·gcdsd 전부 무응답,
물리 리셋 필요). 원인을 단계별 이분 탐색으로 격리했다.

| 단계 | 내용 | 결과 |
|------|------|------|
| 0 | 읽기 전용 | 안전 |
| 1 | `IOSleep(10)` 한 번 | **안전** — 로드 컨텍스트에서 블로킹 가능 |
| 2 | IMC/RCTL/TCTL 정지 | 안전 |
| 3 | PHY 리셋 | 안전 |
| **4** | **글로벌 리셋(CTRL.RST)** | **행** |

처음엔 kern_loader 초기화 컨텍스트에서 슬립한 것이 원인이라 추정했으나
**stage 1이 이를 반증했다.** 진짜 원인은 SDM의 CTRL.RST 설명에 명시돼
있다:

> *"To ensure that global device reset has fully completed and that the
> Ethernet controller responds to subsequent access, wait approximately
> 1 s after setting and before attempting to check to see if the bit has
> cleared **or to access any other device register**."*

문제 코드는 리셋 직후 posted write를 밀어내려고 STATUS를 읽었다
(`regFlush`). **리셋 중인 장치의 레지스터를 건드린 것이다.**

일반 PCI 장치라면 응답 없는 타깃 읽기가 master abort로 끝나 `0xFFFFFFFF`를
돌려주므로 다른 드라이버들(FreeBSD 포함)은 여기서 flush를 해도 무사하다.
**82547EI는 메모리 컨트롤러에 직결된 CSA 포트에 붙어 있어 그 abort 경로가
없다** — 읽기가 영원히 완료되지 않고 CPU가 버스에서 멈춰 머신 전체가
정지한다.

**해결**: RST 기입 후 **어떤 레지스터에도 접근하지 않고** 1.2초 대기
(`RESET_WAIT_MS`). posted write는 알아서 도달하므로 flush가 필요 없다.

### 이 사고에서 얻은 것

- `tools/nxlogd.c` + `tools/nx-logcatch.sh` — 커널 로그를 NFS로 계속
  밀어내는 수집기. 행이 나도 직전까지의 로그가 호스트에 남는다.
  **위험한 시험 전에 반드시 `./tools/nx-logcatch.sh start`.**
- 드라이버의 `CALL` 인자가 단계 선택자다. 한 번에 한 단계씩만 올린다.

## P3 완료 — 수신 경로 (2026-07-20)

디스크립터 링·DMA 버퍼를 만들고 수신기를 켜서 **실제 네트워크
프레임을 받았다.**

```
Pro1000: RX ring virt 0x1f95a000 phys 0xc6ea000 (16 desc, 256 bytes)
Pro1000: 16 RX buffers of 2048 bytes, first phys 0xa952800, last phys 0x9af2000
Pro1000: RX ring programmed, RDBAL 0x0c6ea000 RDLEN 256 RDH 0 RDT 15
Pro1000: receiver enabled, RCTL 0x0400801a - watching 4000 ms
Pro1000: rx[0] 154 bytes  dst 01:80:c2:00:00:0e  src 98:4b:e1:e5:60:e2  type 0x88cc
Pro1000: rx[1]  84 bytes  dst 01:00:5e:00:00:fb  src 7c:d5:66:d6:8f:fe  type 0x0800
Pro1000: rx[2] 104 bytes  dst 33:33:00:00:00:fb  src 7c:d5:66:d6:8f:fe  type 0x86dd
Pro1000: rx[3] 119 bytes  dst 01:80:c2:00:00:00  src fc:ec:da:43:42:36  type 0x0069
Pro1000: rx[4] 119 bytes  dst 01:80:c2:00:00:00  src fc:ec:da:43:42:36  type 0x0069
Pro1000: 5 frames received in 4000 ms (RDH 5, RDT 4)
Pro1000: receiver disabled, RCTL 0x00000000
```

### 받은 것이 진짜 프레임이라는 근거

바이트가 우연히 그럴듯해 보이는 것과 실제로 수신된 것은 다르다.
받은 5개 프레임은 **전부 알려진 프로토콜과 정확히 일치한다.**

| 프레임 | 판별 | 근거 |
|--------|------|------|
| rx[0] | **LLDP** | dst `01:80:c2:00:00:0e` + ethertype `0x88cc` = LLDP 정의 그대로. 스위치가 자기를 광고하는 프레임 |
| rx[1] | **mDNS over IPv4** | dst `01:00:5e:00:00:fb` = 멀티캐스트 224.0.0.251의 MAC 사상, type `0x0800` = IPv4 |
| rx[2] | **mDNS over IPv6** | dst `33:33:...` = IPv6 멀티캐스트, type `0x86dd` = IPv6. **rx[1]과 송신 MAC이 동일** — 같은 호스트가 양쪽 스택으로 mDNS를 내보내는 것과 일치 |
| rx[3], rx[4] | **STP BPDU** | dst `01:80:c2:00:00:00` = STP 브리지 그룹 주소. `0x0069`(105)는 ethertype이 아니라 802.3 길이 필드 — BPDU가 LLC 프레임인 것과 맞다. **두 프레임이 약 2초 간격** = STP hello 주기 |

주소·타입·길이·주기가 서로 독립적으로 앞뒤가 맞는다. DMA가 엉뚱한
곳에 썼다면 이런 일관성은 나올 수 없다. `RDH`가 5로 전진해 수신 개수
5와 일치하는 것도 하드웨어 쪽 카운터로 교차 확인된다.

### DMA 메모리를 안전하게 잡는 법

`IOMalloc`은 **물리적 연속성도 정렬도 보장하지 않는다.** 주소를 잘못
주면 NIC이 남의 물리 메모리를 덮어써 커널이 죽는다. NeXT 자신의
예제(AMDPCSCSIDriver)가 쓰는 방식을 따랐다:

- 필요한 크기의 **2배를 잡고, 페이지 경계를 넘지 않는 절반을 쓴다.**
  한 페이지 안이면 물리적으로 연속임이 정의상 보장된다.
- 그 위에 **물리 주소 쪽에서 한 번 더 검증한다** — 블록 끝의 물리주소가
  시작 + 크기 - 1과 같은지 확인. 아니면 사용을 거부한다.
- 링 베이스의 16바이트 정렬도 명시적으로 확인한다(SDM 13.4.28).

`allocDmaBlock()`이 이 셋을 모두 한다. 하나라도 어긋나면 하드웨어를
건드리기 전에 로그를 남기고 물러난다.

### 해체 순서가 설정만큼 중요하다

디스크립터 링은 곧 해제될 메모리를 가리킨다. 수신기를 켜 둔 채로
메모리를 반납하면 NIC이 커널이 남에게 넘긴 메모리에 계속 쓴다.
`rxRun()`은 반환 전에 `RCTL = 0`으로 수신기를 끄고 그 사실을 읽어
확인한 뒤에야 빠져나오며, 해제는 그다음에 일어난다.

### 마일스톤에 대한 정정

원래 계획의 마일스톤은 `netstat -I en1` 수신 카운트였다. 그것은
**IONetwork 인스턴스 등록**을 전제하는데, 그러려면 아직 미해결인
DriverKit 인스턴스화(부팅 등록) 문제를 먼저 풀어야 한다(P6).

그래서 P3의 판정 기준을 **"실제 프레임이 DMA 버퍼에 도착하는가"**로
바꿨다. RX 엔진·디스크립터 링·DMA가 모두 동작함을 증명한다는 점에서
같은 것을 검증하며, 아직 없는 계층에 의존하지 않는다. 인터럽트 대신
폴링을 쓴 것도 같은 이유다 — 인터럽트 핸들러 등록에는 정식 드라이버
인스턴스가 필요하다.

## P4 완료 — 송신 (2026-07-20)

프레임을 선로에 내보내고, **케이블 반대편 기계가 실제로 받았음까지**
확인했다.

```
Pro1000: TX ring programmed, TDBAL 0x01f53580 TDLEN 128 TCTL 0x000400fa TIPG 0x00602008
Pro1000: sending 60-byte broadcast, ethertype 0x88b5, src 00:16:e6:14:e3:95
Pro1000: TX descriptor done after 50 us (status 0x01, TDH 1)
Pro1000: TPT +1, GPTC +1 (before 0/0, after 1/1)
Pro1000: FRAME TRANSMITTED - hardware counter confirms
Pro1000: burst of 5000 requested, 5000 completed, TPT +5000 GPTC +5000
```

### 세 겹의 증거

| 층위 | 증거 | 말해 주는 것 |
|------|------|--------------|
| 디스크립터 | `status 0x01` (DD), TDH 전진 | 장치가 디스크립터를 처리했다 |
| **하드웨어 카운터** | **`TPT +5000`, `GPTC +5000`** | **MAC이 프레임을 선로에 내보냈다.** GPTC는 *양호한* 패킷만 세므로, 형식이 깨졌다면 TPT만 오르고 GPTC는 오르지 않는다 |
| **케이블 반대편** | 호스트 NIC 수신 **+5260 패킷 / 9초** (배경 ~450) | **다른 기계가 물리적으로 받았다** |

OPENSTEP에는 tcpdump가 없고 호스트에서도 캡처에는 root가 필요하다.
그래서 종단 검증을 **패킷 카운터 차이**로 했다 — 배경 트래픽(초당 약
50패킷)을 먼저 10초간 측정해 두고, 그보다 10배 큰 5000 프레임 버스트를
쏘아 신호가 배경에 묻히지 않게 했다. `/sys/class/net/*/statistics/`는
권한이 필요 없다.

### 카운터 교차검증이 버그를 잡았다

첫 버스트는 **500번 요청에 `TPT +1000`** 을 냈다 — 매 송신이 두 번씩
나가고 있었다. 원인은 디스크립터 0번을 재사용하려고 **`TDH`를 직접 쓴
것**이다. TDH는 하드웨어 소유이며, 동작 중인 송신기 뒤에서 이를 되돌리면
장치가 같은 디스크립터를 다시 보낸다.

고친 방식은 원래 의도된 것 — **링을 순환하며 tail(TDT)만 전진**시킨다.
고친 뒤 `TPT`가 요청 수와 정확히 1:1로 맞았다(5000 요청 → +5000).

디스크립터의 DD 비트만 봤다면 이 버그는 드러나지 않았다. 성공했다고
말하기 전에 **다른 층위의 증거와 대조하는 것**이 실제로 값을 했다.

### 82547 Tx FIFO 에라타에 대하여

계획서는 이 단계에서 워크어라운드를 넣기로 했으나, **넣지 않았다.**
확보한 참고 소스(FreeBSD `e1000_82541.c`, Minix)에는 해당 워크어라운드가
없고, SDM에서 확인되는 것은 82547GI/EI의 PBM이 40KB(기본 TX 18KB /
RX 22KB)로 다른 8254x의 64KB보다 작다는 사실뿐이다. 근거 없이 코드를
넣는 것보다, **지속 부하에서 실제로 stall이 관찰되는지 P5에서 확인한
뒤** 필요하면 그때 근거와 함께 넣는 편이 낫다. 5000 프레임 버스트에서는
아무 문제도 나타나지 않았다.

## P6 진행 중 — DriverKit 인스턴스화 (2026-07-20)

### 메커니즘을 규명했다

`+probe:`를 부르는 주체는 `kl_util`이 아니라 **`/usr/etc/driverLoader`**
였다. `/etc/rc`가 부팅 시 `driverLoader a`(Configure All Devices)를
돌리고, 그때 매칭된 드라이버가 로드되며 probe가 호출된다. 런타임에는
`driverLoader D=<name>`으로 한 장치만 구성할 수 있다.

활성 드라이버를 가르는 것은 번들 안의 **`Instance0.table`** 이다
(감지된 하드웨어의 실제 위치를 담는다). 상세는
[doc/driverkit.md](doc/driverkit.md).

이에 맞춰 `Default.table`을 동작 중인 DEC 21041 드라이버와 같은 형태로
고치고(`"Family" = "Network"`, `"Network Interface" = "AUTO"`,
`"Auto Detect IDs" = "0x10198086"`), `Load_Commands.sect`의 `CALL`
단계를 **0(읽기 전용)으로 고정**했다 — 구성에 성공하면 이 드라이버는
매 부팅마다 로드되므로, 부팅 경로에 리셋이나 DMA를 남겨 둘 수 없다.

### 중단과 그 원인 — 0바이트 번들

`driverLoader D=Pro1000`을 실행하기 직전에 머신이 멈췄고, 재부팅 뒤
`driverLoader`가 응답하지 않았다. 추적해 보니:

1. `kern_loader`(pid 3)가 `RW` 상태로 **CPU를 계속 태우고 있었다**
   (부팅 후 수 분 만에 6분 이상 누적). `kl_util`도 전부 무응답.
2. 설치된 번들을 보니 **모든 파일이 0바이트**였다 —
   `Default.table` 0, `Pro1000_reloc` 0. 정상인 DEC 드라이버는 각각
   523, 43272바이트다.
3. 크래시가 설치 복사 도중 일어나 **디렉터리 항목만 남고 내용이
   유실**된 것이다. 다음 부팅에서 `driverLoader a`가 그 빈 번들을
   읽으려다 `kern_loader`가 루프에 빠졌고, 그 뒤로 드라이버 로드
   경로 전체가 막혔다.
4. 파일을 지워도 **이미 도는 루프는 멈추지 않는다** — 재부팅해야 풀린다.

원래 크래시 자체의 원인은 여전히 불명이다(드라이버는 로드조차 되지
않은 상태였고 커널 로그에도 아무것도 남지 않았다). 다만 **그 이후의
모든 증상은 0바이트 번들로 설명된다.**

**대응**:
- `tools/nx-install-driver.sh` 신설 — 빌드 산출물과 설치본의 크기를
  대조하고 어긋나면 설치본을 지우고 실패로 끝낸다. 손으로 `cp` 하지
  않는다.
- `nx-logcatch`를 세션마다 별도 파일(`logs/kernel-<시각>.log`)에 남기도록
  고쳤다 — 한 파일에 붙이던 방식은 그 파일을 잃으면 지난 증거까지
  함께 사라진다(실제로 이번에 잃었다).

### 다음 단계 설계 (SMC16 구조 기준)

정식 인스턴스는 `IOEthernet` 서브클래스로 만든다. SMC16 예제가 정본:

```objc
+ (BOOL)probe:(IODeviceDescription *)devDesc
    → [[self alloc] initFromDeviceDescription:devDesc] != nil

- initFromDeviceDescription:
    [super initFromDeviceDescription:devDesc]     /* IOEthernet */
    getPCIConfigSpace → BAR0, IRQ
    IOMapPhysicalIntoIOTask(BAR0)
    리셋 → RAL0/RAH0에서 myAddress 획득
    [self resetAndEnable:NO]
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:32]
    network = [super attachToNetworkWithAddress:myAddress]   ← en1 생성

- (BOOL)resetAndEnable:(BOOL)enable     /* 프레임워크가 호출 */
- (IOReturn)enableAllInterrupts / -disableAllInterrupts
- (void)interruptOccurred               /* ICR 판독 → RX/TX 처리 */
- (void)transmit:(netbuf_t)pkt
- (void)timeoutOccurred
```

RX는 인터럽트에서 완료 디스크립터를 훑어 netbuf에 담아
`[network handleInputPacket:pkt extra:0]`으로 올린다. 1차 구현은 우리
DMA 버퍼에서 netbuf로 **복사**한다 — netbuf 데이터를 직접 DMA 대상으로
삼는 최적화는 동작을 확인한 뒤에 한다.

이미 검증된 P1~P4의 코드(매핑·리셋·링크·RX 링·TX 링)가 그대로
들어간다. 새로 필요한 것은 프레임워크 연결부뿐이다.

### 완료 — ping 왕복 성공 (2026-07-20)

```
$ ping 192.0.2.190
64 bytes from 192.0.2.190: icmp_seq=3 ttl=255 time=0.115 ms
4 packets transmitted, 4 received, 0% packet loss
rtt min/avg/max/mdev = 0.093/0.163/0.247/0.062 ms

nextonion# netstat -i
en1  1500  192.0.2    192.0.2.190   64 Ipkts 0 Ierrs  43 Opkts 0 Oerrs 0 Coll
```

수신 64 / 송신 43, **오류 0**. 인터럽트도 정상적으로 흐른다 —
`ICR 0x80`(RXT0)과 `0x03`(TXDW|TXQE)이 번갈아 오고 타임아웃은 사라졌다.
송신 디스크립터도 `desc 1→2→3→4`로 링을 순회한다.

원래 계획의 P3·P4 마일스톤(`netstat -I en1` 카운트, ping 왕복)이 이
단계에서 함께 달성됐다 — 둘 다 IONetwork 통합을 전제했기 때문이다.

### 인터럽트가 오지 않던 이유 — 세 겹이었다

가장 오래 걸린 문제다. 원인이 하나가 아니라 셋이 겹쳐 있었고, 각
층을 벗겨야 다음이 보였다.

| 층 | 문제 | 어떻게 찾았나 |
|---|---|---|
| 1 | device description에 인터럽트가 **0개** | `+probe:`에서 `[devDesc numInterrupts]`를 찍어 확인 → `Instance0.table`에 `"IRQ Levels" = "3"` 추가 |
| 2 | 82547 CSA 메시지 재정렬로 APIC 상태 불일치 | SDM 13.4.20/13.4.21의 82547GI/EI 전용 조항 |
| 3 | **프레임워크 수준 IRQ 미재활성화** | 실측 — 밀린 인터럽트가 항상 `resetAndEnable` 직후에만 도착 |

**1층**: PCI config space에 IRQ 3이 있어도 DriverKit이 그것을 안다는
보장이 없다. `numInterrupts`가 0이면 `-interruptOccurred`는 영원히
호출되지 않는다.

**2층**: SDM이 이 칩에만 요구하는 절차가 있다 —

> *"For the 82547GI/EI, programmers need to first write (clear) the IMS
> and IMC registers due to a Hub Link bus being occupied... two messages
> are re-ordered and sent out. This signals APIC that the 82547GI/EI is
> in a de-asserted state when it is actually in an asserted state, which
> causes a system dead lock. To avoid a system dead lock, first clear
> the IMS and IMC registers by writing FFFFh and then re-assert IRQ
> enable."*

이 칩은 인터럽트를 핀이 아니라 **CSA 허브 인터페이스 메시지**로 보낸다.
그래서 assert/de-assert가 재정렬되면 APIC가 실제와 반대 상태로 남는다.
*"causes a system dead lock"* 이라는 문구가 이 프로젝트에서 겪은 여러
번의 정지와 무관하지 않을 것이다.

**3층**: 위 둘을 다 적용해도 증상이 남았다. 로그를 보면 밀린 인터럽트가
**항상 `resetAndEnable` 직후에만** 도착했고, 그 함수가 하는 일 중
핸들러가 하지 않던 것은 `[super disableAllInterrupts]` →
`[super enableAllInterrupts]` 뿐이었다. DriverKit의 기본 인터럽트
핸들러가 메시지를 보내며 IRQ를 비활성화하고 드라이버가 되살리기를
기대하는 구조로 보인다. 핸들러 끝에서 이 쌍을 부르자 풀렸다.

### 이 과정에서 배운 것

- **계측이 먼저다.** "첫 인터럽트 한 줄"만 찍던 동안에는 원인을 가릴 수
  없어 TXQE 처리·워치독 경쟁 같은 수정을 근거 없이 쌓았고 **전부 원인이
  아니었다.** 인터럽트와 송신을 함께, 각각 12개·5개까지 기록하고 나서야
  "TXDW는 서 있는데 전달만 안 된다"가 보였다.
- **SDM에 있는 대로 고쳤다고 끝이 아니다.** 2층은 문서가 명시한
  요구사항이었지만 그것만으로는 증상이 남았다. 실측으로 확인하지
  않았으면 거기서 멈췄을 것이다.

### en1 생성, 그리고 두 번째 함정

`driverLoader D=Pro1000`이 `+probe:`를 호출했고 인스턴스가 만들어졌다:

```
IP protocol enabled for interface en1, type "10MB Ethernet"
en1: Ethernet address 00:16:e6:14:e3:95
Pro1000: attached to network stack
```

(`"10MB Ethernet"`은 `etherdefs.h`의 `IFTYPE_ETHERNET` 상수로, 속도와
무관한 매체 라벨이다. en0도 같은 문자열을 낸다.)

이어서 `ifconfig en1 <ip> up`을 하자 **머신이 멈췄다.** 로그의
마지막 줄은 `SLU+ASDE set ... - waiting for link`였다.

원인은 **실행 문맥**이다. `ifconfig`는 `-resetAndEnable:YES`를 네트워크
스택의 ioctl 경로에서 부르는데, 거기서 링크 협상을 최대 4초 기다리도록
짜 두었다. 앞서 `CALL`/`probe` 문맥에서는 `IOSleep`이 안전했기 때문에
같은 코드를 그대로 옮긴 것이 화근이었다 — **스택의 락/SPL을 쥔 채
자면 돌아오지 못한다.**

**수정**: 오래 걸리는 일(리셋의 필수 1.2초, 링크 협상 대기)은
`initFromDeviceDescription:`에서 한 번만 하고, `-resetAndEnable:`은
엔진 정지·링 재프로그램·`SLU|ASDE` 설정만 하고 즉시 반환하도록 바꿨다.
링크 결과는 LSC 인터럽트로 받는다. 짧은 정착은 `IOSleep` 대신
`IODelay`(busy-wait)를 쓴다.

같은 세션에서 잡은 다른 두 가지:
- `[self setRunning:]` 누락 — 스택이 인터페이스를 live로 보지 않아
  en1이 생기고도 아무것도 흐르지 않았다. SMC16처럼 반드시 호출한다.
- **네트워크 스택에 붙은 드라이버를 언로드하면 패닉한다**(문서 명시).
  `Load_Commands.sect`에 `DETACH`를 넣어 언로드를 오류로 만들고,
  수정 반영은 재부팅으로 한다.

## P5 — 처리량 실측 (2026-07-20)

같은 프로그램(`../perf/nxperf.c`)으로 검증된 tulip을 먼저 재고, 그다음
동일 조건에서 기가비트를 쟀다. 두 실행의 차이는 NIC 하나뿐이다.

| 방향 | tulip (en0, DEC 21041 10Mb) | **82547EI (en1, 이 드라이버)** | 배수 |
|------|------------------------------|-------------------------------|------|
| 송신 (OPENSTEP → Linux) | 8.15 Mbit/s (16.474 s) | **172.27 Mbit/s (0.779 s)** | **21×** |
| 수신 (Linux → OPENSTEP) | — | **248.63 Mbit/s (0.540 s)** | — |

16MB 전송, 양쪽 끝의 바이트 수와 시간이 정확히 일치했다.

**트래픽이 실제로 en1을 지났다는 확인**: `-B`는 소스 주소만 고정하므로
라우팅이 en0로 흘려보낼 수 있다. `netstat -i`로 대조했다 —
en1의 송신 카운트가 37 → 16479로 뛰었다. 서브넷을 분리할 필요는 없었다.

### 수치 읽기

- **수신이 송신보다 빠르다**(248 vs 172). 수신 경로는 DMA 버퍼를
  netbuf로 복사하는 것이 전부인데, 송신 경로는 netbuf 복사에 더해
  `performLoopback:`을 거친다.
- 기가비트 선속도에 한참 못 미치는 것은 예상대로다 — 1997년 세대 TCP
  스택, 체크섬 오프로드 미사용, 프레임당 복사, 인터럽트 병합(ITR) 없음.
  계획서의 성공 기준("10Mb 대비 대폭 향상, 수십 Mbps")은 크게 넘겼다.
- **Tx FIFO stall 에라타는 나타나지 않았다.** 16MB 연속 송신에서 아무
  이상이 없었다. 근거 없이 워크어라운드를 넣지 않은 판단이 지금까지는
  유효하다. 더 긴 부하로 재확인할 가치는 있다.

### 측정 방법에 대해

사용자 제안이었고, 방법론적으로 옳았다. 절대 수치만 보고했다면 "이
기계가 원래 그 정도인가"를 알 수 없다. **검증된 하드웨어를 같은
도구로 먼저 재는 것**이 비교를 성립시킨다. 도구 자체도 Linux 루프백에서
먼저 검증했다(양쪽 바이트 수 일치).

## P5 — 장시간 부하 (2026-07-20)

512MB / 67만 패킷을 송수신 양방향으로 흘렸다.

```
en1  1500  192.0.2    192.0.2.190   295902 Ipkts 0 Ierrs  377104 Opkts 0 Oerrs 0 Coll
```

드라이버 로그에 타임아웃·경고·실패가 한 건도 없다.

> **위 `0 Ierrs`는 무에러의 증거가 아니다.** 이 측정 시점의 드라이버는
> 통계 카운터를 전혀 기록하지 않았다(아래 "에러 계정" 절 참조). 게다가
> 에러 칸은 주소가 없는 `en1*` 줄에만 채워진다. 근거로 삼을 수 있는
> 것은 로그가 깨끗했다는 사실뿐이다.

| 측정 | 결과 |
|------|------|
| 송신 3회 | 153.57 / 171.90 / 158.57 Mbit/s |
| 수신 3회 | 248.23 / 245.75 / 243.31 Mbit/s |
| 128MB 연속 | 163.55 Mbit/s |

수신 편차가 2% 이내로 안정적이다. 송신이 더 흔들리는 것은
`performLoopback:`과 복사 비용이 CPU 스케줄링에 민감하기 때문으로 보인다.

### Tx FIFO 에라타 — 넣지 않기로 판정

계획서는 P4에서 워크어라운드를 넣기로 했으나, 참고 소스(FreeBSD
`e1000_82541.c`, Minix)에 그런 코드가 없고 SDM도 FIFO 크기만 언급해
보류했었다. **512MB 연속 부하에서도 나타나지 않았다.** 이제 근거를
갖고 넣지 않는다고 판정한다.

단 이는 "이 조건에서 안 나타났다"이지 "에라타가 없다"가 아니다. 더 긴
시간이나 다른 트래픽 패턴에서 나올 여지는 남는다.

## P5 — 멀티캐스트 필터 (2026-07-20)

`IOEthernet`이 요구하는 여섯 메서드(promiscuous 2개, multicast mode
2개, 주소 add/remove 2개)가 전부 비어 있었다. ping이 되니 그냥 지나칠
뻔했다.

### 해시 알고리즘 검증 — SDM의 예제로

MTA는 128 레지스터 = 4096비트 벡터이고, 필터 타입 0의 해시는

```c
hash = ((addr[4] >> 4) | (addr[5] << 4)) & 0xFFF;
```

해시는 조용히 틀리기 쉽다 — 어느 바이트를 쓰는지, 몇 비트 시프트하는지
하나만 어긋나도 **프레임이 안 들어올 뿐 드라이버는 멀쩡해 보인다.**
그래서 산술을 믿지 않고 두 가지로 검증했다:

1. **SDM 자체의 예제와 대조.** 문서가 `01:AA:00:12:34:56`의 해시를
   `0x563`이라고 명시한다. 우리 구현이 같은 값을 냈다.
2. **장치에서 MTA를 되읽어** 해당 비트가 실제로 서 있는지 확인.

```
mcast 01:aa:00:12:34:56 -> hash 0x563, MTA[43] bit 3 = set
mcast 01:00:5e:00:00:fb -> hash 0xfb0, MTA[125] bit 16 = set
multicast self-test passed
```

### 실제 동작 — 부정 대조까지 한 실행에서

mDNS 그룹 둘을 등록한 채 promiscuous를 끄고 배경 트래픽을 관찰했다.
도착한 멀티캐스트는 **전부 등록된 그룹**이었고, 이 네트워크에 2초마다
흐르는 STP BPDU와 LLDP는 **하나도 오지 않았다.** 해시가 그 이유를
설명한다:

| 그룹 | 해시 | MTA 위치 | 등록 | 결과 |
|------|------|----------|------|------|
| STP `01:80:c2:00:00:00` | `0x000` | MTA[0] bit 0 | ✗ | 차단 |
| LLDP `01:80:c2:00:00:0e` | `0x0e0` | MTA[7] bit 0 | ✗ | 차단 |
| mDNS `01:00:5e:00:00:fb` | `0xfb0` | MTA[125] bit 16 | ✓ | 통과 |

통과시킬 것은 통과시키고 차단할 것은 차단한다. 별도 실행 없이 확인됐다.

### 주소 목록을 따로 유지하는 이유

두 주소가 같은 비트로 해시될 수 있다 — 실제로 IPv4/IPv6 mDNS가 둘 다
`0xfb0`이다(끝 두 바이트가 같으므로). 그래서 **제거할 때 비트를 그냥
지우면 다른 주소까지 조용히 안 받게 된다.** 목록에서 전체 테이블을
매번 다시 계산하는 이유다(FreeBSD도 같은 이유로 shadow 배열을 쓴다).

해시 충돌 때문에 하드웨어 필터를 통과한 프레임은 상위에서 한 번 더
걸러야 한다 — 수신 경로의 `[super isUnwantedMulticastPacket:]`이
그 역할을 한다.

## P6 마무리 — 부팅 자동 로드 (2026-07-20)

`System.config`의 **`Instance0.table`** 에 드라이버 이름을 추가하면
부팅 시 자동으로 로드된다. 드라이버 번들과 같은 규칙이 시스템 설정에도
적용된다 — `Default.table`은 템플릿, `InstanceN.table`이 실제 설정이다.
앞서 `Default.table`만 보고 "DEC 드라이버가 목록에 없는데 왜 로드되지?"
했던 것이 이 때문이었다.

```
Default.table:   "Active Drivers" = "PS2Mouse BusMouse SerialPointingDevice ...";
Instance0.table: "Active Drivers" = "PS2Mouse MatroxMGA DECchip21040NetworkDriver Pro1000";
                                                                          ↑ 추가
```

부팅 로그로 확인됐다:

```
Pro1000: attached to network stack
Pro1000: enabled, RCTL 0x04008002 TCTL 0x000400fa STATUS 0x00000383
Pro1000: interrupts flowing, first ICR 0x00000006
Pro1000: link up
```

### 과도기 주의 — 부팅 때마다 잘못된 기본 경로가 생긴다

OPENSTEP의 부팅 네트워크 설정은 **en0만 알고 en1은 모른다**(NetInfo에
항목이 없다). 그래서 en1이 **주소 없이(0.0.0.0) 올라오고**, 그 결과
기본 경로가 둘이 된다:

```
default   192.0.2.1   UG   en0    ← 정상
default   0.0.0.0       U    en1    ← 엉터리
```

지금은 en0 쪽이 쓰이지만 보장된 동작이 아니다. off-subnet 트래픽이
en1로 새면 진단하기 까다로운 고장이 된다. 부팅 후 지울 것:

```sh
./tools/nxrun.sh '/usr/etc/route delete default 0.0.0.0'
```

`ifconfig en1 down`으로는 지워지지 않는다 — 경로를 명시적으로 삭제해야
한다.

**원인은 NIC이 둘이어서가 아니라 `en1`이 NetInfo에 등록돼 있지 않아
주소 없이 올라오는 것이다.** 따라서 tulip을 빼는 것만으로는 사라지지
않는다 — 오히려 **NetInfo 등록이 tulip 제거의 선결 조건**이다. 등록하지
않은 채 en0만 빼면 부팅 후 어떤 인터페이스에도 주소가 없어 기계에
접속할 수단이 사라진다. 순서는 ① en1을 NetInfo에 등록 → ② 부팅 시
주소를 받는지 확인 → ③ 그다음에 tulip 제거다.

> **tulip 제거 시 위험도가 바뀐다.** 지금은 en0가 살아 있어 en1을
> 마음껏 깨뜨려도 원격 접속이 유지된다. tulip을 빼면 **이 드라이버가
> 유일한 접속 경로**가 되고, 드라이버 버그 = 머신 접근 불가가 된다.
> 제거 전에 링크 변동·에러 복구까지 검증을 끝내 둘 것.

## 8254x 계열 지원 (2026-07-20)

PCI 계열 전체를 대상으로 확장했다. PCIe 부품(82571 이후)은 SDM 자체가
다르고, 애초에 이 기계에 PCIe 슬롯이 없어 범위 밖이다.

> **검증 상태: 실기로 확인된 것은 82547EI 하나뿐이다.**
> 나머지는 SDM과 FreeBSD의 부품별 코드에서 따온 것이며, 실제 카드가
> 슬롯에 꽂히기 전까지는 **미검증**이다. 드라이버도 82547EI가 아닌
> 부품을 만나면 로그에 `[UNVERIFIED PART]`를 찍는다.

### 계열이 공유하는 것과 갈리는 것

SDM 한 권이 8254x 전체를 다루며, 레지스터 집합·legacy 디스크립터
형식·멀티캐스트 해시가 공통이다. 이 드라이버의 대부분이 그래서 계열
공통이다. 갈리는 부분만 부품별 플래그로 처리한다:

| 플래그 | 적용 부품 | 근거 |
|--------|-----------|------|
| `Q_PHY_RESET_FIRST` | 82541, 82547 | FreeBSD `e1000_reset_hw_82541()`가 `mac.type`으로 정확히 이 둘만 게이트 |
| `Q_HUB_IMS` | 82547GI/EI | SDM 13.4.20/13.4.21의 CSA 순서 조항 |
| `Q_RESET_VIA_IO` | 82541 (rev 2 포함) | 같은 함수의 `switch` — 64비트 쓰기를 ack하지 못해 I/O 공간으로 리셋 |
| `Q_FIBER` | 파이버·SerDes 변종 | **거부한다**(아래) |

### 파이버·SerDes는 거부한다

파이버 부품은 MAC이 clause 37 PCS로 링크를 협상한다(SDM §8.6). 구리
부품이 내장 PHY로 하는 것(§8.5)과 경로가 다르다. SDM의 각주가 적용
범위를 명확히 가른다:

> §8.5 — *"82541xx, 82547GI/EI, and 82540EP/EM only"*
> §8.6 — *"Applicable to the 82546GB/EB, 82545GM/EM, and 82544GC/EI only"*

이 드라이버는 구리 경로만 구현한다. 그래서 파이버 부품은 감지하되
**초기화를 거부**한다 — 링크가 아예 안 올라오는 편이, 올라온 것처럼
보이면서 프레임을 흘리는 것보다 진단하기 쉽다.

### 검증할 수 없는 코드를 다루는 방식

실기가 없는 경로는 **틀렸을 때 조용히 이상해지지 않도록** 만들었다:

- **I/O BAR를 BAR2로 가정하지 않고 BAR 0~5를 훑는다.** 82547EI에서는
  BAR2가 맞지만 계열 전체에 그 가정이 성립한다는 근거가 없다. 맞는
  기계에서만 동작하는 가정은 다른 기계에서 조용한 함정이 된다.
- **I/O 리셋 전에 조건을 확인하고, 못 갖추면 거부한다.** I/O BAR가
  없거나 PCI 명령 레지스터의 I/O 디코딩이 꺼져 있으면 초기화를
  중단한다. BIOS가 열지 않은 창에 쓰면 남의 장치 포트를 건드릴 수 있고,
  아무도 시험할 수 없는 하드웨어에서 감수할 위험이 아니다.
- I/O 창의 규격은 SDM 13.2.2.1에서 확인했다 — 오프셋 0이 IOADDR,
  4가 IODATA.

## 배포 패키징 (2026-07-20)

`dist/openstep-intel1000-src.tar` — OPENSTEP 머신에 풀어 바로 빌드할 수
있는 소스 묶음. 드라이버, `pcils`(카드 위치·IRQ 확인용), `nxperf`
(처리량 측정), 영문 README가 들어 있다.

- **gz를 쓰지 않는다.** 구세대 tar 환경에서는 단순한 편이 낫다.
- **경로를 짧게 잡았다** — old tar의 100자 제한. 최장 88자이며 make-dist.sh가 초과를 검사한다.
- **생성은 `tools/make-dist.sh`가 한다.** 손으로 묶지 않는다 — 빌드
  산출물과 개발머신 전용 파일을 빼고, 100자 경로 제한을 미리 검사한다.
- **실기에서 검증했다**: 풀어서 README에 적은 명령 그대로 빌드해
  `Pro1000_reloc` **122412 바이트**가 나온다(저장소에서 직접 빌드한
  것과 바이트 단위로 동일). `pcils`와 `nxperf`도 함께 빌드된다.

받는 사람이 반드시 고쳐야 하는 것은 `Instance0.table`의 두 줄이다 —
카드의 PCI 위치와 IRQ. 기계마다 다르고, `pcils`가 알려준다. README에
그 절차를 적었다.

## 에러 계정과 링 고갈 복구 (2026-07-20)

착수 시점에 드러난 사실이 하나 있다. **드라이버는 통계 카운터를 단 한
번도 기록하지 않고 있었다** — `incrementInputErrors` 계열 호출이 코드에
전무했다. 그래서 부하 시험의 `0 Ierrs`는 무에러의 증거가 아니라,
아무것도 쓰지 않은 칸이었다. 문서에 "zero errors"라고 적은 것은 근거
없는 주장이었고 정정했다.

### 무엇을 어디서 세는가 — 중복 집계를 피하는 선택

에러 프레임을 세는 방법이 두 가지 있고, 둘 다 쓰면 한 프레임이 두 번
집계된다.

| 출처 | 쓰는가 | 이유 |
|------|--------|------|
| 디스크립터 error 바이트 | **쓴다** | 프레임 단위로 정확하다 |
| `CRCERRS`·`RLEC`·`RXERRC` | 쓰지 않는다 | 위와 같은 프레임을 다시 센다 |
| `MPC`(FIFO 만원) | **쓴다** | 디스크립터에 도달조차 못 한 프레임 |
| `RNBC`(디스크립터 없음) | **쓴다** | 위와 같음 |
| TX 디스크립터 status | **쓴다** | `CMD_RS` 덕에 판정이 적힌다 |

### SDM이 요구하는데 빠져 있던 초기화

통계 레지스터는 **하드웨어가 초기화하지 않는다.** SDM은 리셋 후 값이
불정이며 RX/TX를 켜기 전에 소프트웨어가 전부 읽어 지우라고 명시한다.
없으면 첫 수확이 전원 투입 시의 쓰레기값을 에러로 보고한다. 또한 이
레지스터들은 **읽으면 0으로 리셋**되고 랩하지 않고 `0xFFFFFFFF`에서
멈추므로, 주기적으로 읽어야 한다(인터럽트 4096회마다).

### 실측 — 링을 일부러 고갈시켰다

UDP로 6초간 40만 패킷을 퍼부었다. 16개짜리 링으로는 감당할 수 없다.

```
Pro1000: receive overrun 10700 (ICR 0x000000d3), 107471 missed
         106073 without a descriptor, if errors 213544
```

- `ICR 0x000000d3`에 `RXO`가 서 있다 — IMS에 추가한 원인이 실제로 온다
- 107471 + 106073 = **213544**, `netstat`의 `Ierrs`와 정확히 일치
- 부하가 끝나자 정상 복귀. 이후 165 Mbit/s 송신에서 신규 에러 0
- **머신은 멈추지 않았다**

### `netstat -i`는 두 줄을 찍는다 — 에러는 아랫줄에만

```
en1   1500  192.0.2  192.0.2.190  299592      0  262457  0  0
en1*  1500  none     none         299592 214279       0  0  0
```

주소가 붙은 윗줄만 보면 에러가 0으로 보인다. 실제로 이것 때문에
"카운터가 동작하지 않는다"고 잘못 판단했다가, 전체 출력을 보고서야
알았다. **`enN*` 줄이 에러가 있는 줄이다.**

### 인터럽트 핸들러 안의 무한 루프 — 스스로 잡은 것

첫 구현의 `_reapTransmit`는 `while (txDone != head)`로 TDH까지
걸어갔다. 응답하지 않는 장치는 all-ones로 읽히므로 `head`가 -1이 되고,
조건이 영원히 참이 된다. **인터럽트 핸들러 안이라 이 머신에서는 돌아올
수 없다.** 범위 검사와 반복 상한을 넣었다. 이 하드웨어에서 장치
레지스터 값을 검증 없이 루프 조건에 쓰는 것은 위험하다.

## 링크 변동 대응 (2026-07-20)

부하(16k pkt/s 송신) 중에 기가비트 랜선을 **2분간** 뽑았다.

```
07:16:11  Pro1000: link down - carrier lost, ...
07:18:17  Pro1000: carrier back - link UP, 1000Mb/s, full duplex
```

- 상태 전이를 추적하므로 각 사건이 **한 번씩만** 찍힌다
- 재연결 시 속도·듀플렉스를 다시 읽어 보고한다. 프로그래밍은 하지
  않는다 — `CTRL.SLU|ASDE`가 서 있어 MAC이 PHY 협상 결과를 자동으로
  따라간다
- 인터페이스는 **스스로 원래 속도로 복귀**했고 전 구간 에러 0
- 트래픽 재개가 케이블보다 1분쯤 늦었는데 TCP 재전송 백오프이지
  드라이버와 무관하다

### 틀렸던 예상 — 워치독은 발화하지 않는다

SDM의 *"indication that the link is not up disables MAC operation"*
문장에서, 링크가 없으면 송신이 완료되지 않아 3초 워치독이 계속
발화하고 결국 `MAX_TX_TIMEOUTS`에 걸려 인터페이스가 영구 정지할
것이라고 예상했다. **2분 동안 TCP가 계속 재전송했는데 워치독은 한 번도
발화하지 않았다.**

즉 캐리어가 없어도 디스크립터 엔진은 디스크립터를 계속 소비하고
write-back 한다 — 프레임이 선로에서 사라질 뿐 TXDW는 온다. 따라서
케이블 뽑힘이 영구 정지로 이어지는 일은 없었고, 그에 대한 방어 코드는
관측된 고장의 수정이 아니라 예방 조치다.

## 1.0 — 진단 로그 정리 (2026-07-20)

버전을 `0.1`에서 **1.0**으로 올렸다. 그 전까지 `Default.table`은
`Pro1000 0.2`, `Instance0.table`은 `Pro1000 0.1`로 서로 달랐다.

### 무엇을 줄였고 무엇을 남겼나

기준은 **"운용자가 알아야 하는가"** 다. 장치의 정체·상태·결과는
남기고, 브링업 단계 추적은 지웠다.

지운 것 — 순수 추적:

`+probe: entered`, `quiesce - masking interrupts`, `quiesce done`,
`asserting PHY_RST`, `PHY_RST survived`, `SLU+ASDE set - waiting for
link`, `RX ring virt/phys`, `N RX buffers of ...`,
`deviceDescription reports N interrupt(s)`

남긴 것 — 정체·위험구간·결과:

- 칩 식별과 BAR0/config IRQ (다른 기계에 설치할 때 필요하다)
- 스테이션 주소, NVM 종류
- `asserting global RST (no register access for 1200 ms)`와
  `global RST survived` — **머신을 두 번 멈춘 구간의 표지다.** 행이
  나면 앞 줄이 마지막 줄이 되어 원인을 정확히 가리킨다
- `link came up after N ms`, `after init: link UP, 1000Mb/s`
- `attached to network stack`
- 요약 줄 `<칩> enabled, N irq, RCTL/TCTL/STATUS`
- `interrupts flowing, first ICR`
- 모든 에러·오버런·링크변동 메시지

`deviceDescription reports ...`를 지운 것은 요약 줄의 `N irq`가 같은
정보를 담기 때문이다. IRQ 진단은 이제 그 줄로 한다
([Pro1000/README-Instance0.md](Pro1000/README-Instance0.md) 참조).

`MANC`는 실제로 하드웨어 ARP 필터링을 껐을 때만 찍는다. 이전에는
`0x3c000002 -> 0x3c000002`처럼 아무것도 바뀌지 않아도 매번 찍었다.

### 반복 메시지의 rate limit을 로그 스케일로

`% 100`은 **6초짜리 UDP 폭주 하나에서 107줄**을 만들어 다른 모든 것을
묻어버렸다. 1·10·100·1000…에서만 찍도록 바꿨다(`logMilestone()`).
같은 폭주가 5줄이 되고, 각 줄에 누적 카운트가 있으므로 총량은 그대로
알 수 있다.

### 검증 — 부팅 로그가 아니라 런타임으로

정리 후 첫 부팅에서 `/usr/adm/messages`에 드라이버 로그가 **한 줄도
없었다.** 드라이버는 정상이었다(`en1` 존재). syslogd가 부팅 도중에
붙으면서 그 이전 커널 메시지를 놓친 것이고, 로그가 단어 중간
(`t up computer without a network`)에서 시작하는 것이 증거다. 즉
부팅 로그는 신뢰할 수 없는 검증 수단이다.

대신 런타임에 같은 6초 UDP 폭주를 다시 걸어 확인했다:

```
Pro1000: receive overrun 1     ... 29 missed 35 without a descriptor, if errors 64
Pro1000: receive overrun 10    ... 161 missed 115 ..., if errors 276
Pro1000: receive overrun 100   ... 960 missed 1004 ..., if errors 1964
Pro1000: receive overrun 1000  ... 7478 missed 9913 ..., if errors 17391
Pro1000: receive overrun 10000 ... 82132 missed 99198 ..., if errors 181330
```

**107줄이 5줄이 됐다.** 덤으로 다섯 줄 전부에서 드라이버 집계
(missed + no-descriptor)가 인터페이스 카운터와 정확히 일치한다 —
29+35=64, 161+115=276, 960+1004=1964, 7478+9913=17391,
82132+99198=181330.

> P1~P3 절에 인용된 실기 로그에는 지금은 없는 줄들이 그대로 남아
> 있다. 당시 기록이므로 손대지 않았다.

## 이후: 남은 항목

로드맵 P1~P6은 전부 닫혔다. 아래 표는 그 기록이고, 실제로 열려 있는
것은 그 다음 절이다.

| 단계 | 내용 | 상태 |
|------|------|------|
| P5 | 멀티캐스트 필터(MTA), 처리량·장시간 부하 | ✅ 완료 |
| P5 | Tx FIFO stall 관찰 여부 | ✅ 미발생 — 워크어라운드 넣지 않기로 종결 |
| P6 | DriverKit 인스턴스화 → 인터럽트 → `IONetwork` → `en1`·ping | ✅ 완료 |

### 아직 남은 것

- 82547EI 외 부품 검증. 계열 코드는 SDM·FreeBSD 기준으로 구현했을 뿐
  실기가 없다. 로그에 `[UNVERIFIED PART]`로 표시된다.
- `en1`의 NetInfo 정식 등록, **그다음에** tulip 제거. 순서를 지킬 것
  (위 "과도기 주의" 참조).
- 부팅 시 `No response from network configuration server.` 지연.
  **원인 미확인.** en1이 주소 없이 올라오는 것과 관련이 있어 보이지만
  확인하지 않았다.
- EEPROM(SPI 비트뱅잉) 접근은 없다. MAC은 하드웨어가 NVM에서
  RAL0/RAH0로 실어 주므로 **당장 필요 없다.** 설정 워드를 읽을 일이
  생기면 그때 구현한다(82547은 EERD가 아니라 EECD 비트뱅잉).
- 송신 배치. 큐잉은 `IONetbufQueue`로 구현돼 있으나 여러 디스크립터를
  한 번에 밀어 넣는 배치 전송은 하지 않는다.

## Installer 패키지(.pkg) (2026-07-24)

일반 사용자용 GUI 설치를 위해 드라이버를 OPENSTEP 네이티브 `.pkg`로 묶었다.

- 도구: `/NextAdmin/Installer.app/package`
  (사용법 `package [-B] [-f] root-dir info-file [tiff-file] [-d dest-dir]`).
- 정의 `pkg/Pro1000.info`: `DefaultLocation /private/Drivers/i386`
  (`/private/Devices`의 실경로 — Installer가 심볼릭 링크에 의존하지 않게
  실경로를 지정), `Application NO`, `Relocatable NO`.
- 빌드 스크립트 `pkg/build-pkg.sh`: 빌드된 `Pro1000.config`를 스테이징 후
  package 실행. OPENSTEP엔 `dirname`이 없어 경로 파생은 sed로, package는
  프롬프트 방지로 stdin을 `/dev/null`로. **gz 없이 `.tar`까지만** 산출.
- 산출물 `pkg/Pro1000.pkg.tar`(커밋). 내부 `Pro1000.tar.Z`가 이미 압축이라
  gz는 무의미. (참고: `dist/`는 gitignore된 소스 tar 위치라 바이너리
  패키지는 `pkg/`에 둔다.)
- **설치는 번들 복사까지만** 한다. 로드/활성화는 Configure.app(또는 이미
  구성돼 있으면 재부팅)로. `.pkg`가 드라이버를 자동 로드하지는 않는다
  (네트워크 스택에 붙은 드라이버 언로드는 패닉 위험이라 post-install
  자동 로드 스크립트는 넣지 않았다).
