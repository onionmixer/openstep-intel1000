# perf — 처리량 측정 도구

`nxperf.c` 하나가 Linux와 OPENSTEP 양쪽에서 컴파일된다. 기존 도구를
쓰지 않고 만든 이유는 **비교 가능성**이다 — 검증된 DEC 21041(10Mb,
OPENSTEP 자체 드라이버)과 Intel 82547EI(기가비트, 우리 드라이버)를
동일한 프로그램·동일한 경로로 재면 두 실행의 차이가 NIC 하나로 좁혀진다.

```
서버:       nxperf -s [-p 포트] [-r] [-n MB]
클라이언트:  nxperf -c <호스트> [-p 포트] [-n MB] [-b 버퍼] [-B 로컬주소] [-r]

  -r   반대 방향(서버가 송신) — 수신 성능 측정
  -B   로컬 주소로 바인드. 두 카드가 같은 서브넷일 때 대상 카드를 고정한다
```

수신 측 수치를 믿는다. 송신 측은 커널에 넘긴 양만 알기 때문이다.

## 빌드

```sh
gcc -O2 -Wall -o nxperf-linux nxperf.c              # 호스트
./tools/nx.sh 'cd /tmp && cp /ndrv/openstep-intel1000/perf/nxperf.c . && cc -O -o nxperf nxperf.c'
```

엄격 C89로 썼다 — `getaddrinfo` 없이 `gethostbyname`/`inet_addr`를 쓰고,
4.3BSD에 없는 `socklen_t`는 자체 typedef한다.

## 사용 예 (실측에 쓴 그대로)

```sh
# 호스트에서 서버
./nxperf-linux -s -p 9930

# OPENSTEP에서 카드를 지정해 송신
./tools/nx.sh '/tmp/nxperf -c <호스트IP> -p 9930 -n 16 -B <en0 IP>'   # tulip 기준선
./tools/nx.sh '/tmp/nxperf -c <호스트IP> -p 9930 -n 16 -B <en1 IP>'   # 기가비트
```

**측정 전후로 `netstat -i`를 확인할 것.** `-B`는 소스 주소만 고정하므로
라우팅이 다른 카드로 흘려보낼 수 있다. 해당 인터페이스의 송수신
카운터가 실제로 증가했는지가 경로의 증거다.

## 결과

[../NOTES.ko.md](../NOTES.ko.md) "P5 — 처리량 실측" 참조.

82547EI 송신 145~172 Mbit/s(최고 172) / 수신 248 Mbit/s, 같은 기계의 tulip(DEC 21041)은
8.15 Mbit/s — 약 21배다.
