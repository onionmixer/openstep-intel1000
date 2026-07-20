# ref/ — 참고 자료

여기 있는 파일들은 **제3자 자료라 저장소에 커밋하지 않는다**
(`.gitignore`가 이 README만 남기고 제외한다). 아래는 각각을 다시
가져오는 방법이다.

| 항목 | 내용 | 취득 방법 |
|------|------|-----------|
| `8254x-sdm.pdf` | Intel *PCI/PCI-X Family of Gigabit Ethernet Controllers SDM* (514p, rev 4.0). 표지에 **82547xx** 명시 — Pro1000의 1차 스펙 | Intel 문서 사이트에서 내려받는다 (파일명 `317453006EN.PDF`) |
| `sdm.txt` | 위 PDF의 텍스트 추출본(검색용) | `pdftotext ref/8254x-sdm.pdf ref/sdm.txt` |
| `minix-e1000/` | Minix3 e1000 드라이버 (BSD 라이선스, ~900줄). **82540EM/82545EM/82540EP만 지원 — 82547은 없다.** 구조 참고용 | `curl -O https://raw.githubusercontent.com/Stichting-MINIX-Research-Foundation/minix/master/minix/drivers/net/e1000/{e1000.c,e1000.h,e1000_hw.h,e1000_reg.h,e1000_pci.h}` |
| `ne2k/` | NE2K 0.91beta 소스 — Linux ne2k-pci의 OPENSTEP DriverKit 포트. PCI 이더넷 드라이버 골격 참고 | 실기의 `/me/temp/NE2K_driver_source/NE2K_0.91beta.m.I.s.tar.gz` |
| `SMC16/` | NeXT 공식 이더넷 드라이버 예제. **빌드 체계의 정본** | 실기의 `/NextDeveloper/Examples/DriverKit/SMC16` |
| `AMDPCSCSIDriver/` | NeXT 공식 PCI 버스마스터 DMA 예제 (`getPCIConfigSpace:`, `IOPhysicalFromVirtual`) | 실기의 `/NextDeveloper/Examples/DriverKit/AMDPCSCSIDriver` |
| `doc-Designing.rtf`, `doc-Utilities.rtf` | NextDev *Writing Loadable Kernel Servers* 문서. `Load_Commands.sect` 문법의 출처 | 실기의 `/NextLibrary/Documentation/NextDev/OperatingSystem/Part2_WritingLKSs/` |
| `freebsd-e1000/` | FreeBSD `em(4)` 소스 일부 (BSD). **82547을 다루는 유일한 참고 구현** — `e1000_82541.c`가 82541/82547 공용, PHY(MDIC/IGP)는 `e1000_phy.c` | `curl -O https://raw.githubusercontent.com/freebsd/freebsd-src/main/sys/dev/e1000/{e1000_82541.c,e1000_phy.c,e1000_mac.c,e1000_nvm.c,e1000_regs.h,e1000_defines.h,e1000_hw.h}` |
| **`openstep/`** | **실기 리소스 로컬 미러** — `headers/`(703개), `makefiles/`, `examples/`(DriverKit 예제 9종), `nextdev-doc/`(NextDev 문서 25MB) | 아래 참조 |

## openstep/ — 실기 리소스 미러 (가장 자주 쓰는 것)

API·예제·문서를 찾을 때 **원격에 묻기 전에 여기를 grep**한다.

```sh
cd openstep-intel1000
grep -rn "IOMapPhysicalIntoIOTask" ref/openstep/headers/
grep -rln "memoryRangeList" ref/openstep/examples/
```

다시 가져오려면 (경로가 짧아지도록 `cd` 후 상대경로로 묶는다 —
**old tar는 경로 100자 제한**이 있다):

```sh
./tools/nx.sh 'cd /NextDeveloper && tar cf /ndrv/openstep-intel1000/ref/openstep/headers.tar Headers'
./tools/nx.sh 'cd / && tar cf /ndrv/openstep-intel1000/ref/openstep/usrinc.tar usr/include'
./tools/nx.sh 'cd /NextDeveloper && tar cf /ndrv/openstep-intel1000/ref/openstep/makefiles.tar Makefiles'
./tools/nx.sh 'cd /NextDeveloper/Examples/DriverKit && tar cf /ndrv/openstep-intel1000/ref/openstep/examples.tar .'
./tools/nx.sh 'cd /NextLibrary/Documentation && tar cf /ndrv/openstep-intel1000/ref/openstep/nextdev-doc.tar NextDev'
cd ref/openstep && for t in headers makefiles examples nextdev-doc; do mkdir -p $t && tar xf $t.tar -C $t; done
```

## 실기에서 가져오는 법

```sh
./tools/nx.sh 'cd /NextDeveloper/Examples/DriverKit && tar cf /tmp/ex.tar SMC16 AMDPCSCSIDriver'
./tools/nx.sh --get /tmp/ex.tar ref/ex.tar && tar xf ref/ex.tar -C ref/ && rm ref/ex.tar
```

## 전부 수집됐다

착수 당시 비어 있던 **FreeBSD `em(4)`**(위 표의 `freebsd-e1000/`)까지
포함해 이 표의 자료는 모두 확보돼 있다. 실제로 쓰인 곳:

- `e1000_82541.c` → 82541/82547의 PHY 선행 리셋과 I/O 공간 리셋 분기
- `e1000_regs.h`·`e1000_defines.h` → 통계 레지스터 오프셋과 디스크립터
  에러/상태 비트. **SDM과 교차 확인한 뒤에 썼다** — 한쪽만 보고
  레지스터 주소를 넣지 않는다
- `8254x-sdm.pdf` → 리셋 대기 시간, MTA 해시, CSA IMS/IMC 순서,
  통계 레지스터 의미(읽으면 리셋, 하드웨어 초기화 없음)

Minix 쪽은 82547을 다루지 않으므로 구조 참고용으로만 썼다.

## 라이선스 주의

- Minix/FreeBSD는 BSD 계열 — 구현 참조로 쓸 수 있다.
- Linux/U-Boot e1000은 GPL — **시퀀스 이해용으로만** 보고 코드를
  옮기지 않는다.
- NeXT 예제와 Intel SDM은 독점 자료다. 저장소에 넣지 않는다.
