# Pro1000 — Intel 82547EI OPENSTEP DriverKit 드라이버 계획

작성 2026-07-20. 첫 드라이버 프로젝트. Intel 8254x 계열 기가비트
컨트롤러용 IOEthernet 드라이버를 OPENSTEP 4.2에 만든다.

> **이 문서는 착수 시점의 설계 판단을 담는다.** 진행 상황과 실측
> 결과는 [README.md](README.md), 남은 일은 [../TODO.md](../TODO.md).
> 실측으로 판정된 항목은 아래에 결과를 적어 두었다.
>
> **현재: 1.0.** 로드맵 P1~P6에 더해 에러 계정·링 고갈 복구, 링크 변동
> 대응, 진단 로그 정리까지 실기 검증했다. 실측 송신 145~172 /
> 수신 248 Mbit/s (82547EI).
> 남은 것은 82547EI 외 부품 검증, `en1`의 NetInfo 등록 후 tulip 제거,
> 부팅 시 네트워크 설정 지연(원인 미확인).

## 0. 핵심 판단 — "PHY 레이어" 문제는 여기선 장벽이 아니다

Linux에서 중단했던 이유였던 PHY 계층(phylib/MDIO 프레임워크)은 8254x
에서는 **필요 없다**:

- 8254x는 MAC이 내장 PHY의 auto-negotiation을 **하드웨어로 자체
  처리**한다. 드라이버는 리셋 후 `CTRL.SLU`(Set Link Up)를 세우고
  `STATUS.LU`/`STATUS.SPEED`를 읽기만 하면 된다.
- PHY 직접 제어가 필요한 경우에도 MDIC 레지스터 폴링 몇 줄이면 되고
  (Minix e1000이 그렇게 한다), 최소 구현에는 그것도 불필요.
- 즉 Linux의 PHY 추상화는 "여러 MAC × 여러 PHY" 조합 문제를 푸는
  프레임워크일 뿐, 단일 칩 대상 드라이버에는 원래 없는 계층이다.

**실측 결과(P2, 2026-07-20): 이 판단이 옳았다.** 82547EI에서 전체
리셋으로 링크를 완전히 끊은 뒤 `CTRL.SLU|ASDE` 두 비트만으로 1.3초
만에 1000Mb/s full duplex가 붙었다. Linux/FreeBSD가 이 계열에 돌리는
`e1000_phy_init_script_82541()`(MDIC 기입 다발)은 **기본 링크에는 필요
없었다.** 그 스크립트는 DSP 튜닝·에라타 회피용이며, 링크 품질 문제가
관찰되면 그때 도입한다.

또한 이번 실기/예제 정찰로 DriverKit에 필요한 빌딩블록이 **전부
존재함**을 확인했다:

| 필요 기능 | 확인된 근거 (전부 ref/에 소스 확보) |
|-----------|--------------------------------------|
| PCI 자동 감지 | NE2K `Default.table`: `"Bus Type" = "PCI"; "Auto Detect IDs" = "0x<dev><ven> ..."` |
| PCI config space 읽기 | NE2K.m:104, AMD_x86.m:77 `[IODirectDevice getPCIConfigSpace:...]` |
| 버스마스터 DMA 물리주소 | AMD_x86.m:256 `IOPhysicalFromVirtual(IOVmTaskSelf(), ...)` |
| 이더넷 프레임워크 | NE2K/SMC16: `IOEthernet` 서브클래스, `IONetwork`, netbuf, transmitQueue |
| 인터럽트 | NE2K `interruptOccurred`, `"Share IRQ Levels" = "YES"` |
| 헤더 | `/NextDeveloper/Headers/driverkit/i386/`: IOPCIDirectDevice.h, IOPCIDeviceDescription.h, PCI.h |

여기에 더해 `pcils` 작업(2026-07-20)으로 **커널 드라이버 빌드·로드
체계 전체가 실증**됐다 — `Makefile.main_driver` 체인, `kl_ld` 커널
로더블 생성, `kl_util -a/-l/-u/-d` 사이클, `Load_Commands.sect`의
`CALL`/`START`. 상세는 `../doc/driverkit.md`. 즉 P1의 "빌드해서 실기
커널에 올린다"는 부분은 이미 통과한 길이다.

착수 시점의 미확인 1건이던 **MMIO 매핑 API도 해소됐다** —
`driverkit/kernelDriver.h`의 `IOMapPhysicalIntoIOTask(phys, len, &virt)`
이며, P1에서 BAR0(`0xe8100000`, 128KB)를 매핑해 레지스터를 읽는 것으로
실증했다. 짝은 `IOUnmapPhysicalFromIOTask()`.

즉 **착수 시점의 열린 질문은 전부 닫혔다.** P6의 DriverKit
인스턴스화도 §6에서 해결됐다. 남은 것은 아래 §5의 리스크뿐이다.

## 1. 대상 하드웨어 — 실기 확정 (2026-07-20, `pcils` 스캔)

대상은 **Intel 82547EI Gigabit Ethernet, `[8086:1019]`, 위치
`02:01.0`** 로 확정됐다. 전체 스캔은 `../pcils/scan-nextonion.txt`.

```
02:01.0 Ethernet controller [0200]: Intel 82547EI Gigabit Ethernet (CSA)
        [8086:1019] rev 00   Subsystem [10cf:11bc] Fujitsu
        IRQ 3, pin A
        BAR0: mem 0xe8100000 (32-bit, non-prefetchable)   ← 레지스터
        BAR2: io  0x2000
```

기계는 Fujitsu 보드의 **Intel 865G + ICH5**. 이더넷 컨트롤러는 둘뿐:

| 위치 | 장치 | 역할 |
|------|------|------|
| 02:01.0 | Intel 82547EI 기가비트 | **이 드라이버의 대상** |
| 03:0b.0 | DEC 21041 Tulip 10Mb `[1011:0014]` | 현재 `en0`, 개발 중 생명줄 |

- **Intel PRO/100(8255x)은 버스에 없다.** 스캔은 완전하다(사용 중인
  버스 0·2·3·4가 전부 스캔 범위 안, 커널 보고 11개 = 해석 11개).
  미장착/접촉불량/BIOS 비활성 중 하나. 만약 나중에 나타나더라도
  **8255x는 8254x와 완전히 다른 MAC**이므로 이 드라이버의 대상이
  아니다(별도 프로젝트가 필요하다). `pcils`의 이름표가 둘을 명시적으로
  구분한다.
- 개발 중 en0(DEC 21041)는 그대로 두고 기가비트를 **en1로 올린다**.
  실험이 깨져도 telnet/gcds 경로가 유지된다.
- Auto Detect IDs 표기(device<<16|vendor): **`"0x10198086"`**.

### 82547EI의 특이점 — 계획에 미치는 영향

- **CSA 버스**: 82547GI/EI는 PCI가 아닌 전용 CSA 포트로 칩셋에 붙는다
  (`00:03.0` PCI-to-CSA Bridge 하위 버스 02). 그러나 SDM이 명시한다 —
  *"Logically, it still follows PCI configuration"*. config space·BAR·
  IRQ 할당이 전부 정상이며(위 스캔이 증거), DriverKit의 PCI 자동감지와
  `getPCIConfigSpace:`가 그대로 통한다. 이전 계획에서 82547을 "범위
  외"로 적었던 것은 **철회한다** — 당시엔 착탈식 카드를 전제했다.
- **64비트 주소 미지원**(SDM 명시) — 어차피 32비트 DMA만 쓸 것이라
  제약이 아니라 오히려 단순화 요인.
- **패킷 FIFO가 40KB**(다른 8254x는 64KB. SDM 기준 기본 배분은 TX 18KB /
  RX 22KB). 착수 시엔 "Tx FIFO stall 에라타 워크어라운드를 P4에서 반드시
  반영"으로 적었으나, **확보한 참고 소스(FreeBSD `e1000_82541.c`, Minix)
  어디에도 그런 워크어라운드가 없고** SDM도 FIFO 크기만 언급한다.
  5000 프레임 버스트에서도 문제가 없었다. **P5의 지속 부하(512MB /
  67만 패킷)에서도 stall이 관찰되지 않아 워크어라운드는 넣지 않기로
  확정했다** — 종결된 결정이다.
- **PHY**: 82547EI는 82541xx와 함께 SDM §8.5 계열(내장 PHY가 clause 40
  auto-negotiation을 **자체 수행**). **P2에서 실측 확정 —
  `CTRL.SLU|ASDE`만으로 충분하고 IGP PHY 초기화 스크립트는 불필요하다.**
- **글로벌 리셋 후 1.2초간 레지스터 접근 금지** (P2에서 머신을 두 번
  하드 행시키고 알아냈다). CSA 포트에는 응답 없는 읽기를 끝내 줄
  master abort 경로가 없어, 리셋 중인 장치를 읽으면 CPU가 버스에서
  멈춘다. 상세는 [README.md](README.md).
- **참고구현 주의**: `ref/minix-e1000`은 82540EM/82545EM/82540EP만
  다루고 82547은 없다. 구조 참고용으로만 쓰고, 82547 특수사항은
  **SDM(`ref/8254x-sdm.pdf`, 82547xx를 표지에 명시)**과 FreeBSD em(4)를
  1차 근거로 삼는다.

## 2. 참고 자료 (수집 대상 → ref/)

- **1차 스펙**: Intel *PCI/PCI-X Family of Gigabit Ethernet
  Controllers Software Developer's Manual* (8254x SDM). 레지스터·
  디스크립터 포맷·초기화 시퀀스의 단일 진실 소스.
- 코드 (라이선스 우선순위 — BSD 계열을 구현 참조로, GPL은 이해용):
  - **Minix3 e1000** (BSD) — ~1천 줄 최소 구현. 우리 구조의 기준.
  - **FreeBSD em(4)** (BSD) — 전 기능·전 변형 레퍼런스.
  - NetBSD wm(4) (BSD).
  - U-Boot e1000, Linux e1000 (GPL — EEPROM/초기화 시퀀스 크로스체크용.
    코드 이식은 하지 않는다).
- DriverKit (확보 완료): `ref/ne2k`(골격 템플릿), `ref/SMC16`(IOEthernet
  정석), `ref/AMDPCSCSIDriver`(PCI+버스마스터 DMA). 실기
  `/NextLibrary/Documentation/NextDev`에 DriverKit 공식 문서.

## 3. 아키텍처

- 클래스 `Pro1000 : IOEthernet`. NE2K의 lksproj 구조를 복제·개명
  (`Pro1000.lksproj`, Load_Commands.sect 포함).
- **MMIO**: BAR0를 커널 가상주소로 매핑해 레지스터 접근 (P1 검증).
- **DMA 링**: RX/TX legacy 디스크립터 링. 물리 연속 메모리 확보 후
  `IOPhysicalFromVirtual`로 물리주소를 링 베이스 레지스터
  (RDBAL/TDBAL)에 기입. 디스크립터 16B 정렬, 링 크기 128B 배수.
  i386 캐시 코히런트라 명시적 sync 불필요.
- **RX**: 2KB 버퍼 × 64~128, RCTL 설정. 인터럽트에서 ICR 판독 →
  RX 처리 → netbuf로 `IONetwork`에 전달.
- **TX**: NE2K와 같은 transmitQueue 패턴, TCTL + 링 기입.
- 범위 외(v1): checksum offload, jumbo, TSO, VLAN, WoL, 통계 상세.

## 4. 단계별 로드맵 — 각 단계는 실기 검증 마일스톤으로 완료 판정

진행 결과는 [README.md](README.md)에 단계별로 기록한다.

| 단계 | 내용 | 마일스톤 | 상태 |
|------|------|----------|------|
| P0 | 참고자료 수집, 빌드 체계 확립 | 예제가 실기에서 빌드된다 | ✅ |
| P1 | 정찰 — config space, BAR0 MMIO 매핑 | 레지스터 값이 IOLog에 | ✅ MAC 판독까지 |
| P2 | MAC 기본 — 리셋, NVM 리로드, 링크 | MAC + "link up 1000Mbps" | ✅ |
| P3 | 수신 — 링/버퍼/RCTL | **프레임이 DMA 버퍼에 도착** | ✅ |
| P4 | 송신 — TX 링/TCTL | **내보낸 프레임을 호스트가 받는다** | ✅ |
| P5 | 안정화 — 멀티캐스트, 에러 복구, 부하 | 장시간 무결함 | ✅ |
| P6 | **DriverKit 인스턴스화 + IONetwork** | `en1` 등록, ping 왕복 | ✅ |

### 마일스톤을 두 번 정정했다

P3·P4의 원래 기준은 `netstat -I en1`과 `ping 왕복`이었다. 둘 다
**IONetwork 인스턴스 등록을 전제**하는데, 그러려면 DriverKit
인스턴스화(부팅 등록) 문제를 먼저 풀어야 한다. 착수 시점에는 그것이
P1에서 자연히 풀릴 줄 알았으나, `+probe:`가 동적 로드로 호출되지
않는다는 사실이 P1에서 드러났다.

그래서 P3·P4는 **그 계층에 의존하지 않는 기준**으로 바꾸고(DMA 버퍼
도착 / 상대가 프레임 수신), IONetwork 통합을 P6로 모아 격상했다.
검증하는 대상(RX·TX 엔진이 실제로 도는가)은 동일하다.

## 5. 리스크와 대응

- ~~**MMIO 매핑 API 불확실**~~ → 해소. `IOMapPhysicalIntoIOTask()`.
- **머신 하드 행 — 실제로 두 번 일어났다.** 예상은 "커널 패닉"이었으나
  실제로는 패닉조차 아닌 버스 스톨이었다(원인은 §1의 리셋 후 접근).
  확립된 대응:
  · **`./tools/nx-logcatch.sh start`** — 커널 로그를 NFS로 밀어내
    행이 나도 직전까지의 로그가 호스트에 남는다. 이 도구 덕에 원인을
    한 번의 행으로 특정했다.
  · **한 번에 한 단계씩** — 브링업 당시엔 `CALL` 인자를 단계
    선택자로 썼다(현재 Pro1000엔 그 진입점이 없다).
    한 단계가 행되면 직전 단계 로그가 이미 호스트에 있어 범인이 명확해진다.
  · 행이 나면 **사용자에게 물리 리셋을 요청**해야 한다.
  · **부팅 자동 로드가 설정돼 있다**(`System.config/Instance0.table`의
    `"Active Drivers"`). 즉 재부팅해도 문제의 드라이버가 다시 올라온다 —
    위험한 변경 전에는 그 목록에서 빼는 것을 고려한다. 0바이트 번들을
    남기면 부팅 자체가 kern_loader 무한 루프에 걸린다.
- **DMA 메모리** — `IOMalloc`은 물리 연속성도 정렬도 보장하지 않는다.
  잘못된 주소는 NIC이 남의 메모리를 덮어쓰는 결과가 된다. 2배 할당 후
  페이지 경계를 피하고 물리주소를 재검증하는 `allocDmaBlock()`을 쓴다
  (P3에서 확립).
- **(선택) QEMU 병행 트랙**: QEMU의 `-device e1000`이 정확히
  82540EM이다. P1~P4를 반복 개발하려던 원래 목적은 실기에서 이미
  끝났으므로 사라졌다. 지금 남은 쓸모는 하나 — **82547EI 외 부품
  검증**이다. 82540EM은 계열 코드 중 예외 처리가 가장 적어 미검증
  경로를 가장 적게 건드린다.
- **성능 기대치 관리**: PCI 32bit/33MHz + 구형 CPU라 기가비트
  선속도는 물리적으로 불가. 기존 10Mb 대비 대폭 향상(수십 Mbps)이면
  성공으로 정의했고, **실측 송신 145~172 / 수신 248 Mbit/s로
  충족했다**(tulip 대비 약 21배).
- **라이선스**: 구현은 Intel SDM + BSD 소스(Minix/FreeBSD) 기준.
  GPL(Linux/U-Boot)은 시퀀스 이해용으로만.

## 6. DriverKit 인스턴스화 — 해결됨

착수 당시 이것이 가장 큰 미지수였다. `+probe:`는 하드웨어가 실재하고
`Auto Detect IDs`가 맞아도 `kl_util` 동적 로드에서는 호출되지 않았고,
그래서 드라이버는 `Load_Commands.sect`의 `CALL` 진입점으로만 돌았다.

규명된 메커니즘:

- **`+probe:`를 부르는 주체는 `kl_util`이 아니라 `driverLoader`다.**
  `/usr/etc/driverLoader D=<name>`이 런타임 경로, `/etc/rc`의
  `driverLoader a`가 부팅 경로다.
- **활성 판정은 `InstanceN.table`의 존재로 한다.** `Default.table`은
  카탈로그일 뿐이고, 기계에서 실제로 발견된 장치를 기술하는 건
  `Instance0.table`이다.
- **인터럽트는 `"IRQ Levels"`가 있어야 배정된다.** 없으면 device
  description이 인터럽트를 0개로 넘겨 `-interruptOccurred`가 영원히
  호출되지 않는다. **부팅 경로도 예외가 아니다** — "부팅 때는 알아서
  배정될 것"이라는 가설을 세웠다가 키를 빼고 재부팅해 `0 irq`를 보고
  반증했다.

그 결과 이 절이 "풀려야 가능하다"고 적었던 것들이 전부 동작한다:
인터럽트 핸들러 등록(폴링 아님), `IONetwork` 등록 → `en1`·`netstat`·
ping 왕복, 부팅 시 자동 로드.

`Configure.app` 등록도 정상이며 드라이버 이름이 제대로 표시된다
(`Configure_APP_SCREENSHOT.png`, 설명은 [README.md](README.md)).
IRQ는 거기서도 지정할 수 있고, 테이블 값만 바꿀 때는 재컴파일이
필요 없다.
