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
pgsynonym은 기본적으로 수퍼유저를 통해서 생성, 삭제 및 권한부여, 회수가 이루어지게됩니다.  
기본적인 생성 순서는 아래와 같습니다.  
1. pgsynonym_create를 통한 시노님 생성
2. pgsynonym_grant를 통한 사용권한 부여

pgsynonym은 기본적으로 시노님의 원본 테이블과 함수, 프로시저에 대한 사용 및 조회권한이 해당 유저에게 부여되어 있다는 것을 전재로 합니다.  
pgsynonym을 처음 create extension 하게되면 시노님의 오너인 pgsynonym 유저와 pgsynonym 스키마가 생성됩니다.  
모든 시노님은 pgsynonym 스키마에 적재되며, 해당 스키마에 대한 사용권한과 시노님에대한 사용권한을 부여받아야만 사용이 가능합니다.  

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
## 주의사항 및 개선예정사항
1. pgsynonym_grant 등을 사용하여 권한을 부여한 경우 search_path에 pgsynonym이 추가되며, 만약 사용하지 않을 경우 alter role을 통한 설정 변경이 필요함.
2. 테이블의 구조 변경을 감지하여 자동 refresh하는 기능 필요.(개선예정)
