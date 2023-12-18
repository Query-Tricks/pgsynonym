# pgsynonym

pgsynonym은 시노님(별명)을 통해 스키마 이름을 붙이지 않고 사용할 수 있도록 구성된 PostgreSQL extension입니다.
PostgreSQL 10버전 이후로 지원하고 있으며, 슈퍼유저로만 `create extension`이 가능합니다.

## pgsynonym 설치방법
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

## pgsynonym 사용방법

#### synonym create
시노님은 `pgsynonym_create('스키마명.오브젝트명', '시노님명')` 함수를 사용해서 생성합니다.
```sql
-- Table to synonym View
select pgsynonym_create('스키마명.테이블명','시노님명')
-- Function to synonym Function
select pgsynonym_create('스키마명.함수명','시노님명')
-- Proceduer to synonym Proceduer
select pgsynonym_create('스키마명.프로시저명','시노님명')
```
#### synonym drop
시노님은 `pgsynonym_drop('시노님명')` 함수를 사용해서 제거합니다.  
시노님의 제거는 동일한 이름으로 지정된 오버로딩된 시노님 전체를 함께 삭제합니다.
```sql
select pgsynonym_drop('시노님명')
```
#### synonym grant
시노님에 대한 권한을 사용권한 부여는 `pgsynonym_grant('부여대상 유저명','시노님명','권한')` 함수를 사용해서 부여합니다.  
```sql
select pgsynonym_grant('부여대상유저명','시노님명','권한')

-- 권한의 경우 ','를 사용하여 한 번에 여러 권한을 지정할 수 있습니다.

select pgsynonym_grant('test_user','test_synonym','select, delete')
select pgsynonym_grant('test_user','test_synonym','select, update')
```
#### synonym revoke
시노님에 대한 권한을 사용권한 회수는 `pgsynonym_revoke('회수대상 유저명','시노님명','권한')` 함수를 사용해서 회수합니다.
```sql
select pgsynonym_revoke('회수대상유저명','시노님명','권한')

-- 권한의 경우 ','를 사용하여 한 번에 여러 권한을 지정할 수 있습니다.

select pgsynonym_revoke('test_user','test_synonym','select, delete')
select pgsynonym_revoke('test_user','test_synonym','select, update')
```
