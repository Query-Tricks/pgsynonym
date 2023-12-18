# pgsynonym

pgsynonym은 시노님(별명)을 통해 스키마 이름을 붙이지 않고 사용할 수 있도록 구성된 PostgreSQL extension입니다.
PostgreSQL 10버전 이후로 지원하고 있으며, 슈퍼유저로만 `create extension`이 가능합니다.

## pgsynonym 사용방법
#### 설치
- 설치파일은 [이곳](https://github.com/Query-Tricks/pgsynonym/releases/tag/latest)에서 다운로드 받을 수 있습니다.
- 설치방법은 아래와 같습니다.
```bash
# setp 01
tar -zxvf pgsynonym-[version].tar.gz

# setp 02
make install
```
```sql
-- step 03
CREATE EXTENSION pgsynonym;
```
