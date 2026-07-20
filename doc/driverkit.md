# DriverKit 개발 노트 (OPENSTEP / NeXT Mach)

실기 확인 전 항목은 **[미검증]** 으로 표기한다.
2026-07-20 실기(nextonion, OPENSTEP 4.2)에서 1차 점검 완료 — 아래
"확인됨" 항목들은 telnet으로 직접 확인한 사실이다.

## 실기 환경 (확인됨, 2026-07-20)

- 컴파일러: `cc-744.13` = **gcc 2.7.2.1** (specs `/lib/i386/specs`),
  make는 `/bin/make`.
- DriverKit 헤더: `/NextDeveloper/Headers/driverkit` 존재.
- 예제: `/NextDeveloper/Examples/DriverKit` — 9종:
  Adaptec1542B, AMDPCSCSIDriver, CirrusLogicGD542X, ProAudioSpectrum16,
  QVision, S3, SMC16(이더넷), SoundBlaster8, TsengLabsET4000.
- 커널 로더 도구: `/usr/etc/kern_loader`, `/usr/etc/kl_util` 존재.
- `/NextAdmin/Configure.app`, `/private/Devices`,
  `/NextLibrary/Documentation/NextDev` 존재.
- **기존 드라이버 작업물이 머신에 이미 있다**: `/me/temp/driver/`,
  `/me/temp/NE2K_driver_source/`, `/me/NE2K_driver_source.tar`
  (NE2000 계열 이더넷 드라이버 소스). 새 드라이버 작업 전 참고할 것.

## 개요

- OPENSTEP의 디바이스 드라이버 프레임워크는 **DriverKit** — Objective-C
  기반. 드라이버는 `IODevice`/`IODirectDevice`(하드웨어 직결) 등의
  서브클래스로 작성한다.
- 드라이버는 **로더블 커널 모듈**로 커널에 적재된다. 사용자 공간
  도구(`/usr/etc/kern_loader`, `/usr/etc/kl_util`)가 로드를 담당한다.
  수동 로드/언로드 절차는 아래 "로드/언로드"에서 확인 완료.

## 드라이버 번들 (.config) — 예제(SoundBlaster8)에서 확인된 구조

```
SoundBlaster8/
├── Makefile                  # PB 생성 — 직접 수정 금지
├── Makefile.preamble         # 커스터마이즈는 여기
├── Makefile.postamble
├── PB.project
├── Default.table             # GLOBAL_RESOURCES — 드라이버 설정 테이블
├── SoundBlaster8.info
├── English.lproj/            # DriverHelp, Localizable.strings
└── SoundBlaster8_reloc.tproj/   # TOOLS 서브프로젝트 — 커널 reloc 빌드
```

- Makefile 핵심: `MAKEFILEDIR = /NextDeveloper/Makefiles/app`,
  `MAKEFILE = bundle.make`, `BUNDLE_EXTENSION = config`.
  즉 산출물은 `<Name>.config` 번들이고, 커널 코드는
  `<Name>_reloc.tproj` 서브프로젝트가 만든다.
- 설치 위치는 `/private/Devices/<Name>.config`. **부팅 시 자동 로드와
  `+probe:` 매칭은 확인 완료** — `InstanceN.table`이 있는 드라이버를
  `driverLoader`가 probe한다("드라이버가 실제로 활성화되는 구조" 참조).
  `Configure.app`도 정상 동작하며 IRQ를 여기서 지정할 수 있다.
  재로드 방식은 드라이버에 따라 다르다 — `DETACH`가 붙은 것은
  `kl_util`로 언로드할 수 없고 재부팅해야 한다(아래).

## 빌드 — 확인 완료 (SMC16·PCIscan 실기 빌드 통과)

정석 구조는 **SMC16 예제**다. NE2K는 더 새 개발환경(Rhapsody) 기준이라
`kernelserver.make`를 참조하는데 **이 머신엔 그 파일이 없다** — NE2K
Makefile을 그대로 쓰면 안 된다.

OPENSTEP 4.2의 드라이버 빌드 체계:

```
<Name>/                       ← 번들 프로젝트
  Makefile                      MAKEFILEDIR=/NextDeveloper/Makefiles/app
                                MAKEFILE=bundle.make, BUNDLE_EXTENSION=config
  Default.table                 GLOBAL_RESOURCES
  English.lproj/Localizable.strings
  <Name>_reloc.tproj/         ← 커널 코드 서브프로젝트 (TOOLS)
    Makefile                    MAKEFILE=tool.make
    Makefile.preamble           MAKEFILEDIR=/NextDeveloper/Makefiles/driverkit
                                MAKEFILE=Makefile.main_driver   ← 핵심
    Makefile.driver_preamble
    Load_Commands.sect
    <Name>.m
```

- 커널 컴파일 플래그(Makefile.main_driver가 제공):
  `-nostdinc -I/NextDeveloper/Headers{,/ansi,/bsd} -DKERNEL
  -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=<Name>_instance -static`
- 링크는 `/usr/bin/kl_ld`가 `.config/<Name>_reloc` 커널 로더블을 생성.
  `<Name>_instance.m`은 빌드가 자동 생성한다.
- **`id`는 Objective-C 예약어** — C 함수의 변수/파라미터 이름으로 쓰면
  `illegal cast, missing ')' after 'id'`가 난다.

## 로드/언로드 — 확인 완료

```sh
/usr/etc/kl_util -a <path>/<Name>_reloc   # 등록(add)
/usr/etc/kl_util -l <Name>                # 로드
/usr/etc/kl_util -s [<Name>]              # 상태
/usr/etc/kl_util -u <Name>                # 언로드
/usr/etc/kl_util -d <Name>                # 등록 해제(delete)
```

- 재등록 전 반드시 `-u` 후 `-d`. 안 하면 `server already exists (106)`.
- 번들은 `/private/Devices/<Name>.config`에 두는 것이 정석.

### 핵심: 하드웨어를 주장하지 않는 모듈은 probe되지 않는다

`kl_util -l`로 로드해도 **DriverKit은 `+probe:`도 `+load`도 호출하지
않는다**(실측). 장치 매칭 없이 코드를 실행하려면 `Load_Commands.sect`의
로드 커맨드를 쓴다:

| 커맨드 | 의미 |
|--------|------|
| `CALL func int` | 서버 초기화 시퀀스 중 전역 함수 `func`를 호출 |
| `START` | 포트 메시지를 기다리지 않고 즉시 기동(포트 없는 서버에 필수) |
| `WIRE` | 코드/데이터를 메모리 상주로 고정(인터럽트 핸들러가 있으면 필수) |
| `SMAP`/`HMAP`/`ADVERTISE` | MiG 메시지 인터페이스용 |
| `DETACH` | 언로드 금지 |

`pcils/PCIscan`이 `CALL`+`START` 방식의 동작 예다. 출처는 실기 문서
`/NextLibrary/Documentation/NextDev/OperatingSystem/Part2_WritingLKSs/`
(`06_Designing`, `_ApA_Utilities`).

## 메모리 매핑 / DMA (확인 완료)

`driverkit/kernelDriver.h` (KERNEL 전용):

```c
IOReturn IOMapPhysicalIntoIOTask(unsigned phys, unsigned len,
                                 vm_address_t *virt);
IOReturn IOUnmapPhysicalFromIOTask(vm_address_t virt, unsigned len);
IOReturn IOPhysicalFromVirtual(vm_task_t task, vm_address_t virt,
                               unsigned *phys);   /* DMA용 역방향 */
vm_task_t IOVmTaskSelf(void);
```

- **MMIO(PCI BAR) 매핑은 `IOMapPhysicalIntoIOTask`** — intel1000 P1에서
  82547EI의 BAR0(phys `0xe8100000`, 128KB)를 매핑해 레지스터를 읽는
  것으로 실증했다. 레지스터 접근은 `volatile unsigned long *`로 한다.
- DMA 버퍼의 물리주소는 `IOPhysicalFromVirtual(IOVmTaskSelf(), ...)`
  (AMDPCSCSIDriver 예제가 이 패턴을 쓴다).
- **`IOMalloc`은 물리적 연속성도 정렬도 보장하지 않는다.** DMA에 쓸
  메모리는 NeXT 자신의 관용구를 따른다 — **필요한 크기의 2배를 잡고,
  페이지 경계를 넘지 않는 절반을 쓴다**(한 페이지 안이면 연속임이
  정의상 보장). 그 위에 블록 끝의 물리주소가 `시작 + 크기 - 1`과
  같은지 재검증한다. 구현 예: `openstep-intel1000`의 `allocDmaBlock()`.
- `IOMallocLow()`(i386/kernelDriver.h)는 16MB 이하 메모리 — ISA DMA용.
- **DMA 엔진을 끄고 꺼진 것을 확인한 뒤에 메모리를 해제할 것.**
  링이 가리키는 메모리를 먼저 반납하면 장치가 남의 메모리에 계속 쓴다.
- 디스플레이 드라이버는 `mapFrameBufferAtPhysicalAddress:` 래퍼를 쓴다
  (S3 예제 참고).

## 드라이버가 실제로 활성화되는 구조 (2026-07-20 규명)

`/private/Devices`는 **`/private/Drivers/i386`의 심볼릭 링크**다. 같은
디렉터리이며, 이 기계에는 86개 드라이버 번들이 들어 있다.

**활성 드라이버를 가르는 것은 `InstanceN.table`의 존재다.** 86개 중
`Instance0.table`을 가진 11개가 부팅 시 로드된 것들과 정확히 일치했다
(DECchip21040NetworkDriver=en0, MatroxMGA=Display0, ISASerialPort,
PS2Keyboard/Mouse, EIDE, Floppy, 버스 드라이버들).

`Instance0.table`은 **감지된 하드웨어의 실제 위치**를 담는다. 동작 중인
DEC 21041의 것:

```
"Driver Name" = "DECchip21041";
"Auto Detect IDs" = "0x00141011";
"Location" = "Dev:11 Func:0 Bus:3";     ← 실제 PCI 위치
"Default Table" = "DEC21041";
"Server Name" = "DECchip21040NetworkDriver";
```

`Default.table`은 그 드라이버가 지원하는 장치의 카탈로그이고,
`InstanceN.table`은 **이 기계에서 실제로 발견된 개체**의 기록이다.

### 그것을 만드는 것: `/usr/etc/driverLoader`

```
Usage: /usr/etc/driverLoader <operation> [v(verbose)]
    a               Configure All Devices
    i               Interactive mode
    d=deviceName    Configure one device (implies interactive)
    D=deviceName    Configure one device (non-interactive)
```

`/etc/rc`가 부팅 시 `driverLoader a`를 실행한다(52~55행). 즉 부팅
때마다 전체 장치 구성이 돌고, 그 과정에서 매칭된 드라이버가 로드되며
`+probe:`가 호출된다.

**따라서 `+probe:`를 부르는 주체는 `kl_util`이 아니라 `driverLoader`다.**
`kl_util -l`은 서버를 커널에 올릴 뿐 장치 매칭을 하지 않는다 — 앞서
관찰한 "동적 로드로는 probe되지 않는다"의 정체가 이것이다.

> **주의 1**: `driverLoader`로 구성에 성공하면 `InstanceN.table`이 생겨
> **이후 매 부팅마다 로드된다.** 부팅 경로에 들어가는 드라이버는
> `Load_Commands.sect`의 `CALL` 단계를 읽기 전용으로 낮춰 두어야 한다.
> 부팅 중 행되면 복구가 훨씬 어렵다.
>
> **주의 2 — 0바이트 번들은 `kern_loader`를 무한 루프에 빠뜨린다.**
> 2026-07-20에 크래시로 복사가 끊겨 `Default.table`과 `<Name>_reloc`이
> 0바이트로 남았다. 다음 부팅에서 `driverLoader a`가 그것을 읽으려다
> **`kern_loader`(pid 3)가 CPU를 계속 태우는 상태**가 되었고, 그 뒤로
> `kl_util`은 전부 무응답, `driverLoader`도 그 데몬을 기다리다 멈췄다.
> 파일을 지워도 이미 도는 루프는 멈추지 않아 **재부팅해야 풀린다.**
>
> 그래서 설치는 항상 **`./tools/nx-install-driver.sh <번들경로>`** 로
> 한다 — 빌드 산출물과 설치본의 크기를 대조하고, 어긋나면 설치본을
> 지우고 실패로 끝낸다. 손으로 `cp` 하지 말 것.

## PCI 드라이버 매칭 — `kl_util` 동적 로드로는 probe되지 않는다

`Default.table`에 `"Bus Type" = "PCI"`와 올바른
`"Auto Detect IDs"`(= device<<16|vendor, 예 `"0x10198086"`)를 넣고
**실재하는 하드웨어**를 지정해도, `kl_util -l`로 동적 로드하면
`+probe:`가 호출되지 않는다(intel1000 P1에서 확인). `kl_util`은 모듈을
커널에 올릴 뿐이고, **`+probe:`를 부르는 주체는 `driverLoader`다** —
`InstanceN.table`이 있는 드라이버에 대해서만 그렇게 한다(위 "드라이버가
실제로 활성화되는 구조" 참조). 추측이 아니라 실측으로 규명된 것이다.

개발 중에는 `Load_Commands.sect`의 `CALL` 진입점에서 config space를
직접 훑어 장치를 찾는 자립 경로를 두면 매칭에 의존하지 않고 진행할 수
있다 (`openstep-intel1000/Pro1000/Pro1000_reloc.tproj/Pro1000.m`이 두 경로를 모두 가진
예다).

## 인터럽트를 받으려면 세 가지가 다 맞아야 한다

intel1000에서 인터럽트가 전달되지 않아 오래 헤맸다. 원인이 셋이 겹쳐
있었고, 각각 독립적으로 필요하다.

**1. device description이 인터럽트를 알아야 한다.**
PCI config space에 IRQ가 있어도 DriverKit이 안다는 보장이 없다.
`+probe:`에서 확인할 것:

```objc
IOLog("... %d interrupt(s), first %d\n",
      [devDesc numInterrupts],
      ([devDesc numInterrupts] > 0) ? [devDesc interrupt] : -1);
```

0이면 `-interruptOccurred`는 영원히 호출되지 않는다. `InstanceN.table`에
`"IRQ Levels" = "<번호>"` 를 넣어 해결했다(값은 `pcils`로 확인한
BIOS 배정값). 그 파일이 기계별 값의 자리다 — 드라이버 코드가 아니라.

**부팅 경로를 포함한 모든 로드 경로에서 필수다.** "부팅 때는
`driverLoader a`가 알아서 배정해 줄 것"이라는 가설을 세웠다가
실측으로 반증했다 — 키를 빼고 재부팅하니 로그에 `0 irq`가 찍혔다.
`Configure.app`의 IRQ Level 행렬이 쓰는 키도 이것이며, 거기서 고르든
손으로 적든 드라이버 소스는 건드릴 필요가 없다. 값만 바꿀 때는
**재컴파일도 필요 없다** — 다시 설치하고 재부팅하면 된다.

**2. 칩 고유의 인터럽트 요구사항.**
82547GI/EI는 인터럽트를 핀이 아니라 CSA 허브 메시지로 보내며, SDM이
IMS/IMC를 `FFFFh`로 먼저 지운 뒤 마스크를 재설정하라고 요구한다
(13.4.20/13.4.21). 안 지키면 APIC가 실제와 반대 상태로 남고 SDM 표현
그대로 *"system dead lock"* 이 된다. 칩별 조항은 SDM에서 직접 확인할 것.

**3. 핸들러 끝에서 프레임워크 IRQ를 재활성화해야 한다.**

```objc
- (void)interruptOccurred
{
    do { cause = regRead(base, ICR); ... } while (cause != 0);

    [self disableAllInterrupts];
    [self enableAllInterrupts];   /* ← 이게 없으면 다음 인터럽트가 안 온다 */
}
```

DriverKit의 기본 인터럽트 핸들러가 메시지를 보내며 IRQ를 비활성화하고
드라이버가 되살리기를 기대하는 구조로 보인다. 이것이 빠지면 **첫
인터럽트만 오고 그 뒤로 오지 않는다** — 장치 쪽 원인 비트는 계속 쌓여
있다가 다음 `resetAndEnable` 때 한꺼번에 도착한다. 그 관찰이 원인을
지목한 결정적 단서였다.

### 진단 요령

증상이 "인터럽트가 안 온다"일 때 코드를 고치기 전에 **먼저 측정**한다.
인터럽트 N개와 송신 N개를 각각 상한을 두고 기록하면(로그 폭주 방지),
"신호가 안 오는 것"과 "와도 처리가 잘못된 것"이 구분된다. 이 구분 없이
고치면 근거 없는 수정만 쌓인다 — 실제로 그렇게 됐다.

## 네트워크 스택에 붙은 드라이버는 언로드하면 패닉한다

`attachToNetworkWithAddress:`로 `IONetwork`에 붙고 나면 커널이 그 모듈
안의 코드·데이터를 가리키게 된다. 그 상태에서 `kl_util -u` 하면 —

> *"When the server is unloaded, no other part of the kernel can contain
> a reference to any code or data contained within the loadable server.
> If the kernel tries to refer to any code or data in an unloaded
> server, the system panics."*
> — NextDev, *Designing Loadable Kernel Servers*

2026-07-20에 실제로 이렇게 패닉을 냈다. 대응:

- `Load_Commands.sect`에 **`DETACH`** 를 넣는다. kern_loader가 언로드
  요청을 **오류로 처리**하므로 패닉 대신 실패로 끝난다. 문서도
  *"necessary for the correctness of some network protocols"* 라고
  적고 있다.
- 설치는 `tools/nx-install-driver.sh`로 한다 — 이미 로드된 드라이버를
  발견하면 **언로드하지 않고** 설치만 한 뒤 재부팅이 필요하다고 알린다.
- **대가**: 네트워크 드라이버는 고칠 때마다 재부팅해야 반영된다.
  패닉보다 낫다.

## 실행 문맥마다 허용되는 것이 다르다

같은 코드라도 어디서 불리느냐에 따라 안전 여부가 갈린다. 실측으로
확인한 것:

| 문맥 | 진입 경로 | 블로킹(`IOSleep`) |
|------|-----------|-------------------|
| kern_loader 로드 | `Load_Commands.sect`의 `CALL` | **가능** (초 단위도 OK) |
| driverLoader probe | `+probe:` → `initFromDeviceDescription:` | **가능** |
| 네트워크 스택 ioctl | `ifconfig` → `-resetAndEnable:` | **불가 — 머신이 멈춘다** |
| 인터럽트 핸들러 | `-interruptOccurred` | 불가 |

`ifconfig en1 <ip> up`이 `-resetAndEnable:YES`를 부르는데, 그 안에서
링크 협상을 최대 4초 기다리도록 짰다가 시스템을 통째로 멈췄다
(2026-07-20). 네트워크 스택의 락/SPL을 쥔 채 자면 돌아오지 못한다.

**설계 원칙**: 오래 걸리는 일(장치 리셋의 필수 1.2초 대기, 링크
협상 대기)은 **`initFromDeviceDescription:`에서 한 번** 하고,
`-resetAndEnable:`은 엔진 정지·링 재프로그램·`SLU|ASDE` 설정만 하고
즉시 반환한다. 링크 결과는 **LSC 인터럽트**로 받는다. 짧은 정착
시간이 꼭 필요하면 `IOSleep`이 아니라 **`IODelay`**(마이크로초 단위
busy-wait)를 쓴다 — 어떤 SPL에서도 안전하다.

## 하드웨어를 건드릴 때의 안전 수칙 (실제로 머신을 멈춰 본 뒤)

- **응답하지 않을 수 있는 장치의 레지스터를 읽지 말 것.** 이 기계에는
  그 읽기를 끝내 줄 장치가 없을 수 있고(CSA 포트), 그러면 CPU가
  버스에서 멈춰 커널 전체가 정지한다. 패닉조차 아니라 아무 로그도
  남지 않는다. 실제 사례: 82547EI의 `CTRL.RST` 직후 read-back
  (`openstep-intel1000/NOTES.ko.md`).
- **커널 로그를 NFS로 밀어낼 것** — `./tools/nx-logcatch.sh start`.
  행이 나면 `/usr/adm/messages`는 버퍼 캐시에 갇힌 채 사라진다.
- **변경은 한 단계씩.** `Load_Commands.sect`의 `CALL` 인자를 단계
  선택자로 쓰면, 한 단계가 행되어도 직전 단계 로그가 호스트에 남아
  원인이 명확해진다. 짐작으로 고치면 엉뚱한 곳을 손대게 된다 —
  실제로 첫 가설(로드 컨텍스트에서의 `IOSleep`)은 틀렸고, 단계 시험이
  그것을 반증했다.

## 유저랜드 제약

- **유저랜드는 IN/OUT을 실행할 수 없다**(실측: SIGILL). 포트 I/O가
  필요한 진단은 전부 커널 모듈로 가야 한다. `pcils`가 그 패턴이다.
- 커널→유저랜드 간이 전달은 `IOLog` → syslog → `/usr/adm/messages`.
  제대로 된 양방향 인터페이스가 필요하면 MiG(`SMAP`/`HMAP`).
- 유저랜드 DriverKit API는 `IODeviceMaster`(등록된 장치 조회용).

## 디버깅

- 커널 내 `IOLog()` 출력은 콘솔과 `/usr/adm/messages`로 간다(확인됨).
  syslog가 `mach:` 접두어를 붙인다.
- **행/패닉이 나면 `/usr/adm/messages`의 마지막 기록은 사라진다** —
  버퍼 캐시에 있던 채로 머신이 멈추기 때문. `nx-logcatch`가 NFS로
  밀어낸 사본(`logs/kernel.log`)을 봐야 한다.
- 시리얼 콘솔 캡처(GCDS `gcdslog`, /dev/ttya 9600)는 아직 연결하지
  않았다. NFS 밀어내기로 지금까지는 충분했다.
- 머신이 죽으면 telnet/gcdsd 모두 무응답 — 사용자에게 물리 리셋
  요청이 필요하다.

## 워크플로 요약

1. 호스트에서 소스 편집 (드라이버별 하위 폴더).
2. 재부팅 직후라면 `./tools/nx-mount.sh` + `./tools/nx-daemon.sh start`
   — gcdsd는 재부팅을 넘기지 못한다.
3. `./tools/nx-install-driver.sh openstep-intel1000/Pro1000`
   — `/tmp`로 복사해 빌드하고(공유 트리를 더럽히지 않는다), 설치 후
   **크기를 검증**한다. 손으로 `cp` 하지 않는다.
4. 반영:
   - `DETACH`가 있는 드라이버(Pro1000 등 네트워크 스택에 붙는 것)는
     **재부팅**한다. `kl_util -u`는 설계상 에러가 된다.
   - 하드웨어를 주장하지 않는 진단 모듈(PCIscan 등)만
     `kl_util -a` → `-l`, 재등록 전 `-u` → `-d` 주기를 쓴다.
5. **테이블만 고칠 때는 재컴파일이 필요 없다** — 컴파일되는 건
   `*_reloc` 하나뿐이고 `.table`은 번들 안의 평문이다. 다시 설치하고
   재부팅하면 된다.
6. 결과·함정은 이 문서와 각 드라이버 폴더 README에 기록.

> 실기 시계는 호스트와 몇 년씩 어긋나 있다. **두 머신의 파일
> timestamp를 비교하지 말 것** — `nx-install-driver.sh`가 mtime이 아니라
> **크기**를 대조하는 이유다.

절차 전체와 문제 해결은 [workflow.md](workflow.md).
