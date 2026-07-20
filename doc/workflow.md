# 개발 워크플로

호스트(Linux)에서 편집하고 OPENSTEP 실기에서 네이티브 빌드·실행하는
사이클. 실제 주소·토큰은 gitignore된 `etc/site.conf`에 있고, 아래
설명은 모두 그 값을 읽는 도구를 통한다.

## 0. 최초 1회 설정

```sh
cp etc/site.conf.sample etc/site.conf     # 주소·토큰 채우기
./tools/gen-conf.sh                       # etc/gcds.cnf, remote/gcdsd.cnf 생성
```

## 1. 세션 시작 (호스트/실기 재부팅 후 매번)

무엇 하나도 자동으로 뜨지 않는다. 순서대로:

```sh
sudo ./tools/serve-src.sh      # ① gnfsd - 워크스페이스를 NFS export
                               #    (portmap 111 바인딩에 root 필요)
./tools/nx-fixroute.sh         # ② en1의 엉터리 기본 경로 정리
./tools/nx-mount.sh            # ③ OPENSTEP에서 /ndrv 마운트
./tools/nx-daemon.sh start     # ④ gcdsd 기동 (포트 9910)
```

②를 먼저 하는 이유: **en1이 NetInfo에 등록돼 있지 않아** 부팅 때 주소
없이(0.0.0.0) 올라오고, 그 결과 `default 0.0.0.0 U en1`이라는 기본
경로가 하나 더 생긴다. 정리하지 않으면 off-subnet 트래픽이 en1로 샐 수
있다. 저절로 사라지지 않는다 — **en1을 NetInfo에 등록해야** 없어지며,
그 등록은 tulip을 제거하기 위한 선결 조건이기도 하다(등록 없이 en0만
빼면 기계에 접속할 수 없게 된다).

④는 매번 필요하다. **gcdsd는 재부팅을 넘기지 못한다.**

각 단계의 상세와 문제 해결은 **HANDOFF.md**(내부 전용)에 있다.

## 2. 두 갈래 원격 실행 — 셸이 다르다

| 도구 | 경로 | 원격 셸 | 쓰임 |
|------|------|---------|------|
| `tools/nx.sh` | gcds → gcdsd:9910 | **sh** | 기본. 스트리밍 출력 + exit code 보존 |
| `tools/nxrun.sh` | telnet + expect | **csh** | gcdsd가 죽었을 때, 또는 데몬 자체를 다룰 때 |
| `tools/nxsh.sh` | telnet 대화형 | csh | 손으로 뒤져볼 때 |

```sh
./tools/nx.sh 'cd /tmp && cc -O -o pcils /ndrv/openstep-intel1000/pcils/pcils.c'
./tools/nx.sh --get /tmp/out.txt out.txt      # 원격 → 호스트
./tools/nx.sh --put local.bin /tmp/in.bin     # 호스트 → 원격
```

**리다이렉트 문법을 섞지 말 것**: sh는 `2>&1`, csh는 `>&`.
csh에는 `mkdir -p`가 없다(`-p`라는 디렉터리가 생긴다).

## 3. 실기 리소스는 통째로 가져와 로컬에서 본다

**OPENSTEP에 원격 명령을 반복해 뒤지지 말 것.** 헤더·예제·문서를
tar로 묶어 NFS 공유에 넣고 호스트에서 검토하는 편이 훨씬 빠르고
정확하다. 원격 grep은 왕복이 느린 데다, NeXT의 `grep`은 `-r`이
없고 `du`는 `-k`가 없는 등 도구가 옛날 것이라 헛수고가 되기 쉽다.

```sh
# 실기에서 tar로 묶어 공유에 떨군다 (경로가 짧아지도록 cd 후 상대경로로)
./tools/nx.sh 'cd /NextDeveloper && tar cf /ndrv/openstep-intel1000/ref/openstep/headers.tar Headers'
./tools/nx.sh 'cd /NextDeveloper/Examples/DriverKit && tar cf /ndrv/openstep-intel1000/ref/openstep/examples.tar .'

# 호스트에서 풀어서 마음껏 검색
cd ref/openstep && tar xf headers.tar -C headers
grep -rn "IOMapPhysicalIntoIOTask" headers/
```

`ref/openstep/`에 이미 헤더·Makefile·예제·NextDev 문서를 받아 두었다
(내용은 [../ref/README.md](../ref/README.md)). 새 API나 예제를 찾을 일이
생기면 원격에 묻기 전에 **먼저 여기를 검색한다.**

- **old tar는 경로 100자 제한**이 있다. `cd`로 기준을 낮춰 상대경로로
  묶어야 긴 이름(예: ProAudioSpectrum16)이 잘리지 않는다.
- 실기 자료는 독점물이라 `ref/`는 gitignore된다.

## 4. 편집 → 빌드 사이클

소스는 호스트에서 편집한다. NFS 공유라 OPENSTEP이 바로 본다.

**산출물을 공유 트리에 흘리지 않는다.** 빌드는 `i386_obj/`·`sym/`·
`*.config/`를 잔뜩 만들고, 그 뒤에 있는 NFS 서버는 단일 스레드다.

```sh
# 유저랜드 프로그램 — 출력은 /tmp로
./tools/nx.sh 'cd /tmp && cc -O -Wall -o pcils /ndrv/openstep-intel1000/pcils/pcils.c && ./pcils'

# 커널 드라이버 — /tmp로 복사해서 빌드
./tools/nx.sh 'rm -rf /tmp/X && cp -r /ndrv/openstep-intel1000/pcils/PCIscan /tmp/X && cd /tmp/X && make'

# 드라이버 번들은 그냥 이걸 쓴다 (위 과정 + 설치 + 크기 검증)
./tools/nx-install-driver.sh openstep-intel1000/pcils/PCIscan
```

- **OPENSTEP이 바뀐 소스를 못 볼 때**: 드물다 — 마운트 옵션에 `noac`가
  있어 속성 캐시가 꺼져 있다. 그래도 의심되면 `./tools/nx-mount.sh`
  재실행이 umount→mount로 캐시를 비운다.
- **`/ndrv`가 비어 보이거나 `No such file or directory`가 날 때**:
  마운트가 풀린 것이다. `nx-mount.sh`로 다시 붙인다.
- **재마운트가 `Device busy`로 거부될 때**: soft 마운트가 실패하면
  NeXTSTEP 쪽에 잔여 상태가 남는다(`mount` 목록에는 안 보이는데도
  busy). 잠금 자체는 재부팅해야 풀리지만, 그 전에도 다른 지점에
  마운트해 우회할 수 있다 — `MOUNTPT`는 환경에서 덮어쓸 수 있다:

  ```sh
  MOUNTPT=/ndrv2 ./tools/nx-install-driver.sh openstep-intel1000/Pro1000
  ```

  파일 하나 정도는 NFS 없이 `./tools/nx.sh --put`으로 보낼 수 있다.
- 커널 드라이버 빌드는 산출물(`i386_obj/`, `sym/`, `*.config/`)이 많이
  나오므로 공유 트리를 더럽히지 않게 `/tmp`에서 빌드하는 편이 낫다.

## 5. 커널 드라이버 로드 사이클

```sh
./tools/nx-install-driver.sh openstep-intel1000/Pro1000   # 빌드+설치+크기검증
# 반영은 재부팅. 이후:
./tools/nxrun.sh 'grep Pro1000 /usr/adm/messages | tail -15'
```

**설치는 반드시 `nx-install-driver.sh`로 한다.** 손으로 `cp` 하면
0바이트 번들이 남을 수 있고, 그러면 다음 부팅에서 `kern_loader`가
무한 루프에 빠져 재부팅해야만 풀린다(2026-07-20 실제 사례).

**Pro1000은 `kl_util`로 재로드하지 않는다.** `Load_Commands.sect`에
`DETACH`가 있어 언로드가 설계상 에러가 되며, 네트워크 스택에 붙은
드라이버를 억지로 언로드하면 커널이 패닉한다. 반영 수단은 재부팅뿐이다.
`kl_util -a`/`-l`, 그리고 재등록 전 `-u`→`-d`(빼먹으면
`server already exists (106)`) 주기는 **하드웨어를 주장하지 않는 진단
모듈**(PCIscan 등)에만 해당한다.

**테이블만 바꿀 때는 재컴파일이 필요 없다.** 컴파일되는 건
`Pro1000_reloc` 하나뿐이고 `Default.table`·`Instance0.table`은 번들 안의
평문이다. 다시 설치하고 재부팅하면 된다.

빌드 규약과 로드 커맨드(`CALL`/`START`/`WIRE`/`DETACH`)는
[driverkit.md](driverkit.md) 참조.

### 부팅 시 커널 메시지는 유실될 수 있다

`/usr/adm/messages`에 드라이버의 부팅 로그가 **한 줄도 없는 부팅을
관측했다**(2026-07-20). 드라이버가 로드되지 않은 것이 아니라 —
`ifconfig`에 인터페이스가 정상적으로 있었다 — syslogd가 부팅 도중에
붙으면서 그 이전 커널 메시지를 놓친 것이다. 증거는 로그가 단어 중간에서
시작한다는 것이다:

```
Apr  5 07:34:49 nextonion mach: t up computer without a network
Apr  5 07:34:49 nextonion mach: connection.
```

즉 **부팅 로그의 부재는 드라이버가 안 떴다는 뜻이 아니다.** 확인은
`ifconfig`로 하고, 로그가 필요하면 런타임에 다시 유발한다(예:
`nx-logcatch.sh` 가동 후 부하를 걸어 에러 경로를 태운다).

## 6. 커널이 죽었을 때

**위험한 드라이버 시험 전에는 반드시 로그 수집기를 켠다.**

```sh
./tools/nx-logcatch.sh start      # 커널 로그를 NFS로 계속 밀어냄
./tools/nx-logcatch.sh show       # 호스트에 쌓인 로그 보기 (logs/kernel.log)
```

커널이 행되면 `/usr/adm/messages`의 마지막 기록은 버퍼 캐시에 갇힌 채
사라진다 — 머신이 flush할 기회를 못 얻기 때문이다. `nxlogd`가 한
줄씩 NFS로 fsync하며 밀어내므로 **행 직전까지의 로그가 호스트 디스크에
남고**, 대상이 죽어 있는 동안에도 읽을 수 있다. 실제로 이 도구 덕에
82547EI의 리셋 행 원인을 한 번의 행으로 특정했다.

위험한 변경은 **한 번에 하나씩** 올린다. 브링업 단계에서는
`Load_Commands.sect`의 `CALL` 인자를 단계 선택자로 써서 한 단계씩
올렸다(지금 Pro1000에는 그 진입점이 없다 — `pcils/PCIscan`이 같은
방식을 쓴다).


드라이버 실험은 패닉을 부른다. 패닉이 나면 telnet·gcdsd·NFS가 전부
무응답이 되고 **원격으로 할 수 있는 일이 없다** — 사용자에게 물리
리셋을 요청해야 한다.

줄이는 방법:

- 소스는 항상 호스트(NFS 서버) 쪽에 있으므로 소스 유실은 없다.
- 실험 전 `/me`에 있는 것 중 남길 게 있으면 NFS로 복사해 둔다.
- **en0(DEC 21041)는 건드리지 않는다.** 그게 유일한 접속 경로다.
  기가비트는 en1로 올린다.
- 패닉 메시지를 봐야 하면 GCDS의 `gcdslog`로 시리얼 콘솔을 받는다
  (`/dev/ttya`, 9600). userland에서는 패닉 순간을 잡을 수 없다.

### NFS가 자꾸 풀리는 이유

`gnfsd`는 **단일 스레드**다(`rpc.c`의 select 루프가 요청을 하나씩
처리). 여기에 `noac`(속성 캐시 끔)가 겹치면 빌드처럼 파일 수백 개를
훑는 작업이 GETATTR을 폭증시킨다. 원래 쓰던 `timeo=10`(1.0초)·
`retrans=3`에서는 서버가 잠깐 밀리는 것만으로 연산이 실패했고,
soft 마운트 실패가 위의 `Device busy` 상태로 이어졌다.

그래서 `timeo=30`(3.0초)·`retrans=5`로 늘렸다. `noac`는 유지한다 —
소스 갱신 즉시 반영이 이 작업 흐름의 전제이고, remount에만 의존하면
언젠가 오래된 소스로 빌드하게 된다.

## 7. 도구 목록

| 스크립트 | 하는 일 |
|----------|---------|
| `tools/site.sh` | `etc/site.conf` 로더 (다른 스크립트가 source) |
| `tools/gen-conf.sh` | site.conf → `etc/gcds.cnf`, `remote/gcdsd.cnf` |
| `tools/serve-src.sh` | gnfsd로 워크스페이스 export (sudo) |
| `tools/nx-mount.sh` | OPENSTEP에서 `/ndrv` 마운트/언마운트 |
| `tools/nx-daemon.sh` | gcdsd 배포·기동·상태 |
| `tools/nx-fixroute.sh` | 부팅 시 생기는 엉터리 기본 경로 정리 |
| `tools/nx.sh` | gcds 원격 실행/파일전송 (권장) |
| `tools/nxrun.sh` | telnet 한 줄 실행 (csh) |
| `tools/nxsh.sh` | telnet 대화형 |
| `tools/check-env.csh` | OPENSTEP 개발환경 점검 (실기에서 실행) |
| `tools/next-mount-driver.csh` | 실기에 두고 쓰는 마운트 스크립트(선택) |
| `tools/nx-install-driver.sh` | 드라이버 번들 빌드·설치·**크기 검증** |
| `tools/nx-logcatch.sh` | 커널 로그를 NFS로 밀어내는 수집기 제어 |
| `tools/nxlogd.c` | 위 수집기 본체 (실기에서 빌드·상주) |
| `tools/smoke.c` | 전 구간 점검용 최소 C 프로그램 |
| `openstep-intel1000/tools/make-dist.sh` | 배포 tar 생성(손으로 묶지 않는다) |
