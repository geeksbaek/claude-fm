import Foundation

/// 영어 읽기 사전. 한 줄에 `낱말 읽기`, 구절 사전의 `_` 는 띄어쓰기다.
extension HangulReading {
    static let phraseLexiconTable = """
    not at all 나래롤
    at all 애롤
    it all 이롤
    that all 대롤
    for all 포올
    after all 애프터롤
    don't you 돈츄
    dont you 돈츄
    won't you 원츄
    wont you 원츄
    can't you 캔츄
    cant you 캔츄
    didn't you 디든츄
    didnt you 디든츄
    wouldn't you 우든츄
    wouldnt you 우든츄
    couldn't you 쿠든츄
    couldnt you 쿠든츄
    shouldn't you 슈든츄
    shouldnt you 슈든츄
    aren't you 안츄
    arent you 안츄
    isn't you 이즌츄
    isnt you 이즌츄
    did you 디쥬
    would you 우쥬
    could you 쿠쥬
    should you 슈쥬
    had you 해쥬
    want you 원츄
    wanted you 워니쥬
    need you 니쥬
    needed you 니디쥬
    got you 가츄
    get you 게츄
    let you 레츄
    set you 쎄츄
    put you 푸츄
    hit you 히츄
    meet you 미츄
    bet you 베츄
    hate you 헤이츄
    hurt you 허츄
    trust you 트러스츄
    hold you 홀쥬
    told you 톨쥬
    find you 파인쥬
    found you 파운쥬
    around you 어라운쥬
    behind you 비하인쥬
    beside you 비싸이쥬
    inside you 인싸이쥬
    without you 위다우츄
    about you 어바우츄
    with you 위츄
    miss you 미쓔
    kiss you 키쓔
    pass you 패쓔
    bless you 블레쓔
    lose you 루쥬
    use you 유쥬
    choose you 추쥬
    close you 클로쥬
    cause you 커쥬
    'cause you 커쥬
    because you 비커쥬
    what you 와츄
    that you 대츄
    when you 웨뉴
    if you 이퓨
    of you 어뷰
    love you 러뷰
    give you 기뷰
    leave you 리뷰
    save you 쎄이뷰
    have you 해뷰
    tell you 텔유
    call you 콜유
    feel you 필유
    want to 워너
    going to 거너
    got to 가러
    ought to 오러
    have to 해프투
    has to 해스투
    had to 해투
    used to 유스투
    supposed to 써포즈투
    trying to 트라이너
    out of 아우러브
    kind of 카인더
    sort of 쏘러
    lot of 라러
    lots of 라츠어브
    all of 올러브
    full of 풀러브
    tired of 타이어더브
    sick of 씨커브
    think of 띵커브
    dream of 드리머브
    made of 메이더브
    afraid of 어프레이더브
    instead of 인스테더브
    front of 프런터브
    top of 타퍼브
    side of 싸이더브
    part of 파러브
    heart of 하러브
    end of 엔더브
    middle of 미들러브
    rest of 레스터브
    best of 베스터브
    most of 모스터브
    none of 너너브
    one of 워너브
    some of 써머브
    both of 보써브
    each of 이쳐브
    let me 레미
    give me 기미
    tell me 텔미
    call me 콜미
    feel me 필미
    hold me 홀미
    find me 파인미
    send me 쎈미
    mind me 마인미
    remind me 리마인미
    behind me 비하인미
    around me 어라운미
    let it 레릿
    get it 게릿
    got it 가릿
    put it 푸릿
    hit it 히릿
    set it 쎄릿
    cut it 커릿
    shut it 셔릿
    forget it 포게릿
    make it 메이킷
    take it 테이킷
    shake it 쉐이킷
    break it 브레이킷
    fake it 페이킷
    like it 라이킷
    kick it 키킷
    rock it 라킷
    check it 체킷
    work it 워킷
    keep it 키핏
    drop it 드라핏
    stop it 스타핏
    pop it 파핏
    hold it 홀딧
    find it 파인딧
    need it 니딧
    read it 리딧
    feel it 필릿
    call it 콜릿
    pull it 풀릿
    tell it 텔릿
    fill it 필릿
    kill it 킬릿
    roll it 롤릿
    say it 쎄잇
    do it 두잇
    know it 노잇
    throw it 쓰로잇
    show it 쇼잇
    blow it 블로잇
    grow it 그로잇
    lose it 루짓
    use it 유짓
    choose it 추짓
    close it 클로짓
    love it 러빗
    give it 기빗
    leave it 리빗
    live it 리빗
    have it 해빗
    move it 무빗
    prove it 프루빗
    save it 쎄이빗
    touch it 터칫
    watch it 와칫
    catch it 캐칫
    reach it 리칫
    push it 푸쉣
    wish it 위쉣
    worth it 워씟
    with it 위딧
    in it 이닛
    on it 오닛
    is it 이짓
    was it 워짓
    does it 더짓
    come on 커몬
    hold on 홀돈
    move on 무본
    go on 고온
    keep on 키폰
    put on 푸론
    get on 게론
    sit on 씨론
    wait on 웨이론
    right on 라이론
    turn on 터논
    hang on 행온
    count on 카운톤
    depend on 디펜돈
    come in 커민
    fall in 폴린
    all in 올린
    fill in 필린
    call in 콜린
    pull in 풀린
    roll in 롤린
    give in 기빈
    live in 리빈
    believe in 빌리빈
    deep in 디핀
    step in 스테핀
    drop in 드라핀
    jump in 점핀
    back in 배킨
    stuck in 스터킨
    lock in 라킨
    kick in 키킨
    walk in 워킨
    sink in 씽킨
    break in 브레이킨
    take in 테이킨
    lost in 로스틴
    get in 게린
    let in 레린
    put in 푸린
    fit in 피린
    sit in 씨린
    wake up 웨이컵
    make up 메이컵
    take up 테이컵
    break up 브레이컵
    shake up 쉐이컵
    pick up 피컵
    look up 루컵
    lock up 라컵
    back up 배컵
    pack up 패컵
    hook up 후컵
    fuck up 퍼컵
    shut up 셔럽
    get up 게럽
    got up 가럽
    put up 푸럽
    set up 쎄럽
    cut up 커럽
    light up 라이럽
    lit up 리럽
    heat up 히럽
    split up 스플리럽
    start up 스타럽
    caught up 코럽
    give up 기법
    gave up 게이법
    live up 리법
    save up 쎄이법
    keep up 키펍
    step up 스테펍
    wrap up 래펍
    pop up 파펍
    end up 엔덥
    stand up 스탠덥
    hold up 홀덥
    build up 빌덥
    fold up 폴더업
    pull up 풀럽
    fill up 필럽
    call up 콜럽
    roll up 롤럽
    turn up 터넙
    burn up 버넙
    open up 오프넙
    clean up 클리넙
    run up 러넙
    grow up 그로업
    show up 쇼업
    blow up 블로업
    slow up 슬로업
    throw up 쓰로업
    go up 고업
    wake me 웨잌미
    make me 메잌미
    take me 테잌미
    break me 브레잌미
    shake me 쉐잌미
    like me 라잌미
    let out 레라웃
    get out 게라웃
    got out 가라웃
    put out 푸라웃
    cut out 커라웃
    set out 쎄라웃
    sit out 씨라웃
    shut out 셔라웃
    spit out 스피라웃
    right out 라이라웃
    night out 나이라웃
    light out 라이라웃
    shout out 샤우라웃
    find out 파인다웃
    found out 파운다웃
    stand out 스탠다웃
    hand out 핸다웃
    hold out 홀다웃
    fade out 페이다웃
    hide out 하이다웃
    ride out 라이다웃
    slide out 슬라이다웃
    work out 워카웃
    walk out 워카웃
    talk out 토카웃
    look out 루카웃
    check out 체카웃
    black out 블래카웃
    knock out 나카웃
    lock out 라카웃
    rock out 라카웃
    break out 브레이카웃
    take out 테이카웃
    make out 메이카웃
    shake out 쉐이카웃
    freak out 프리카웃
    speak out 스피카웃
    sneak out 스니카웃
    stick out 스티카웃
    kick out 키카웃
    pick out 피카웃
    step out 스테파웃
    drop out 드라파웃
    keep out 키파웃
    pop out 파파웃
    slip out 슬리파웃
    flip out 플리파웃
    trip out 트리파웃
    help out 헬파웃
    jump out 점파웃
    run out 러나웃
    ran out 래나웃
    burn out 버나웃
    turn out 터나웃
    worn out 워나웃
    all out 올라웃
    fall out 폴라웃
    call out 콜라웃
    pull out 풀라웃
    roll out 롤라웃
    sell out 쎌라웃
    chill out 칠라웃
    spell out 스펠라웃
    fill out 필라웃
    watch out 와챠웃
    reach out 리챠웃
    stretch out 스트레챠웃
    catch out 캐챠웃
    wash out 워샤웃
    push out 푸샤웃
    rush out 러샤웃
    crash out 크래샤웃
    pass out 패싸웃
    miss out 미싸웃
    cross out 크로싸웃
    go out 고아웃
    throw out 쓰로아웃
    blow out 블로아웃
    show out 쇼아웃
    grow out 그로아웃
    figure out 피겨라웃
    look at 루캣
    back at 배캣
    laugh at 래팻
    right now 라잇_나우
    good night 군나잇
    all night 올라잇
    all right 올라잇
    alright 올라잇
    last night 래스나잇
    one more 원_모어
    no more 노_모어
    once more 원스_모어
    right here 라잇_히어
    right there 라잇_데어
    out there 아웃_데어
    in there 인_데어
    over there 오버_데어
    up there 업_데어
    down there 다운_데어
    """

    static let lexiconTable = """
    a 어
    i 아이
    the 더
    an 언
    oh 오
    yeah 예
    yes 예스
    no 노
    go 고
    so 쏘
    know 노
    dont 돈트
    don't 돈트
    can't 캔트
    cant 캔트
    wont 원트
    won't 원트
    didnt 디든트
    didn't 디든트
    wouldnt 우든트
    wouldn't 우든트
    couldnt 쿠든트
    couldn't 쿠든트
    shouldnt 슈든트
    shouldn't 슈든트
    isnt 이즌트
    isn't 이즌트
    arent 안트
    aren't 안트
    wasnt 워즌트
    wasn't 워즌트
    werent 원트
    weren't 원트
    havent 해븐트
    haven't 해븐트
    hasnt 해즌트
    hasn't 해즌트
    hadnt 해든트
    hadn't 해든트
    zero 제로
    one 원
    two 투
    three 쓰리
    four 포
    five 파이브
    six 씩스
    seven 쎄븐
    eight 에잇
    nine 나인
    ten 텐
    eleven 일레븐
    twelve 트웰브
    thirteen 써틴
    fourteen 포틴
    fifteen 피프틴
    sixteen 씩스틴
    seventeen 쎄븐틴
    eighteen 에이틴
    nineteen 나인틴
    twenty 트웬티
    thirty 써리
    forty 포리
    fifty 피프티
    sixty 씩스티
    seventy 쎄븐티
    eighty 에이리
    ninety 나인티
    hundred 헌드레드
    thousand 싸우전드
    million 밀리언
    billion 빌리언
    first 퍼스트
    second 쎄컨드
    third 써드
    fourth 포쓰
    fifth 피프쓰
    sixth 씩스쓰
    seventh 쎄븐쓰
    eighth 에잇쓰
    ninth 나인쓰
    tenth 텐쓰
    percent 퍼센트
    point 포인트
    time 타임
    life 라이프
    world 월드
    girl 걸
    boy 보이
    man 맨
    woman 우먼
    feel 필
    feeling 필링
    feels 필즈
    away 어웨이
    tonight 투나잇
    today 투데이
    tomorrow 투마로우
    yesterday 예스터데이
    music 뮤직
    song 쏭
    songs 쏭즈
    sing 씽
    singing 씽잉
    sings 씽즈
    sang 쌩
    sung 썽
    dance 댄스
    dancing 댄싱
    light 라잇
    lights 라이츠
    lighter 라이러
    lighting 라이링
    dark 다크
    star 스타
    stars 스타즈
    sky 스카이
    eyes 아이즈
    eye 아이
    smile 스마일
    kiss 키스
    hold 홀드
    holding 홀딩
    hand 핸드
    hands 핸즈
    soul 쏘울
    sound 싸운드
    sounds 싸운즈
    side 싸이드
    sides 싸이즈
    same 쎄임
    some 썸
    soon 쑨
    sad 쌔드
    safe 쎄이프
    save 쎄이브
    saving 쎄이빙
    sick 씩
    sit 씻
    sitting 씨링
    such 써치
    suck 썩
    super 쑤퍼
    season 씨즌
    seasons 씨즌즈
    secret 씨크릿
    secrets 씨크릿츠
    sex 쎅스
    sexy 쎅시
    send 쎈드
    sense 쎈스
    since 씬스
    simple 씸플
    single 씽글
    silver 씰버
    mind 마인드
    body 바디
    beautiful 뷰리풀
    beauty 뷰리
    crazy 크레이지
    lonely 론리
    happy 해피
    blue 블루
    red 레드
    black 블랙
    white 와잇
    gold 골드
    rain 레인
    sun 썬
    sunny 써니
    sunday 썬데이
    moon 문
    home 홈
    love 러브
    loved 러브드
    loving 러빙
    lover 러버
    loves 러브즈
    heart 하트
    hearts 하츠
    day 데이
    days 데이즈
    morning 모닝
    free 프리
    real 리얼
    true 트루
    right 라잇
    stop 스탑
    wait 웨잇
    waiting 웨이링
    stay 스테이
    leave 리브
    leaving 리빙
    gone 곤
    die 다이
    dying 다잉
    live 리브
    living 리빙
    alive 얼라이브
    cry 크라이
    crying 크라잉
    pain 페인
    fall 폴
    falling 폴링
    run 런
    running 러닝
    walk 워크
    walking 워킹
    rock 락
    roll 롤
    rolling 롤링
    beat 빝
    rhythm 리듬
    phone 폰
    call 콜
    calling 콜링
    voice 보이스
    name 네임
    face 페이스
    touch 터치
    friend 프렌드
    friends 프렌즈
    people 피플
    everything 에브리띵
    everyone 에브리원
    anything 애니띵
    anyone 애니원
    nothing 너씽
    something 썸씽
    someone 썸원
    somebody 썸바디
    nobody 노바디
    anybody 애니바디
    thing 띵
    things 띵즈
    money 머니
    power 파워
    party 파리
    dream 드림
    dreams 드림즈
    dreaming 드리밍
    sleep 슬립
    sleeping 슬리핑
    goodbye 굿바이
    hello 헬로
    sorry 쏘리
    please 플리즈
    thanks 땡스
    thank 땡크
    king 킹
    queen 퀸
    angel 에인절
    fire 파이어
    burn 번
    burning 버닝
    cold 콜드
    hot 핫
    cool 쿨
    water 워러
    tears 티어즈
    broken 브로큰
    high 하이
    low 로우
    up 업
    down 다운
    out 아웃
    over 오버
    under 언더
    again 어게인
    never 네버
    always 올웨이즈
    forever 포레버
    whatever 와레버
    whenever 웨네버
    wherever 웨어레버
    however 하우에버
    together 투게더
    alone 얼론
    only 온리
    just 저스트
    like 라잌
    likes 라잌스
    want 원트
    wanted 워니드
    wanting 원팅
    need 니드
    needed 니디드
    take 테잌
    takes 테잌스
    taking 테이킹
    make 메잌
    makes 메잌스
    making 메이킹
    wake 웨잌
    waking 웨이킹
    fake 페잌
    mistake 미스테잌
    heartbreak 하트브레잌
    give 기브
    giving 기빙
    let 렛
    letting 레링
    come 컴
    coming 커밍
    back 백
    now 나우
    here 히어
    there 데어
    where 웨어
    when 웬
    what 왓
    who 후
    why 와이
    how 하우
    this 디스
    that 댓
    these 디즈
    those 도즈
    with 위드
    without 위다웃
    within 위딘
    from 프럼
    your 유어
    youre 유어
    you're 유어
    im 아임
    i'm 아임
    its 잇츠
    it's 잇츠
    we're 위어
    they're 데어
    theyre 데어
    you've 유브
    we've 위브
    they've 데이브
    you'll 유을
    we'll 위을
    they'll 데일
    he's 히즈
    she's 쉬즈
    they 데이
    them 뎀
    their 데어
    theirs 데어즈
    me 미
    my 마이
    mine 마인
    we 위
    us 어스
    he 히
    him 힘
    his 히즈
    she 쉬
    her 허
    hers 허즈
    it 잇
    to 투
    of 어브
    and 앤드
    in 인
    on 온
    at 앳
    by 바이
    for 포
    is 이즈
    be 비
    been 빈
    being 비잉
    am 앰
    are 아
    was 워즈
    were 워
    but 벗
    if 이프
    or 오어
    not 낫
    can 캔
    will 윌
    all 올
    about 어바웃
    into 인투
    through 쓰루
    because 비커즈
    cause 커즈
    'cause 커즈
    cuz 커즈
    gonna 거너
    wanna 워너
    gotta 가러
    outta 아우러
    lemme 레미
    gimme 기미
    imma 아이머
    dunno 더노
    tryna 트라이너
    hey 헤이
    la 라
    na 나
    ooh 우
    whoa 워
    wow 와우
    baby 베이비
    babe 베이브
    darling 달링
    honey 허니
    sweet 스윝
    little 리를
    bottle 바를
    battle 배를
    settle 쎄를
    good 굿
    bad 배드
    new 뉴
    old 올드
    young 영
    long 롱
    way 웨이
    ways 웨이즈
    shine 샤인
    shining 샤이닝
    bright 브라잇
    sight 싸잇
    fight 파잇
    fighting 파이링
    tight 타잇
    flight 플라잇
    might 마잇
    late 레잇
    later 레이러
    hate 헤잇
    hating 헤이링
    fate 페잇
    state 스테잇
    date 데잇
    gate 게잇
    memory 메모리
    memories 메모리즈
    remember 리멤버
    forget 포겟
    miss 미스
    missing 미씽
    think 띵크
    thinking 띵킹
    say 쎄이
    says 쎄즈
    said 쎄드
    tell 텔
    telling 텔링
    talk 토크
    talking 토킹
    word 워드
    words 워즈
    story 스토리
    melody 멜로디
    move 무브
    moving 무빙
    shake 쉐잌
    shaking 쉐이킹
    turn 턴
    turning 터닝
    around 어라운드
    still 스틸
    maybe 메이비
    really 리얼리
    every 에브리
    everybody 에브리바디
    somewhere 썸웨어
    wonderful 원더풀
    pretty 프리리
    magic 매직
    heaven 헤븐
    hell 헬
    god 갓
    lord 로드
    night 나잇
    nights 나이츠
    you 유
    ya 야
    yo 요
    let's 레츠
    lets 레츠
    i'll 아일
    i'd 아이드
    i've 아이브
    play 플레이
    playing 플레잉
    game 게임
    ain't 에인트
    what's 왓츠
    that's 댓츠
    there's 데어즈
    here's 히어즈
    who's 후즈
    kinda 카인더
    bye 바이
    sugar 슈거
    heartbeat 하트빝
    fly 플라이
    flying 플라잉
    higher 하이어
    believe 빌리브
    believing 빌리빙
    hope 호프
    hopeless 호플리스
    place 플레이스
    firework 파이어웤
    worth 워쓰
    peach 피치
    peaches 피치즈
    georgia 조지아
    warm 웜
    church 처치
    worship 워쉽
    dog 도그
    lie 라이
    lies 라이즈
    stranger 스트레인저
    strangers 스트레인저즈
    exchange 익스체인지
    exchanging 익스체인징
    glance 글랜스
    glances 글랜시즈
    wonder 원더
    wondering 원더링
    chance 챈스
    chances 챈시즈
    change 체인지
    changing 체인징
    oughta 오러
    much 머치
    smooth 스무드
    criminal 크리미널
    automatic 오토매틱
    systematic 씨스테매틱
    hydromatic 하이드로매틱
    thought 쏘트
    caught 코트
    bought 보트
    brought 브로트
    fought 포트
    taught 토트
    enough 이너프
    tough 터프
    rough 러프
    laugh 래프
    ghost 고스트
    most 모스트
    lost 로스트
    both 보쓰
    truth 트루쓰
    youth 유쓰
    south 싸우쓰
    mouth 마우쓰
    earth 어쓰
    breath 브레쓰
    breathe 브리드
    breathing 브리딩
    blood 블러드
    double 더블
    trouble 트러블
    couple 커플
    country 컨트리
    front 프런트
    done 던
    none 넌
    son 썬
    won 원
    once 원스
    ocean 오션
    emotion 이모션
    vision 비전
    even 이븐
    ever 에버
    heavy 헤비
    ready 레디
    already 올레디
    head 헤드
    dead 데드
    instead 인스테드
    weather 웨더
    pleasure 플레저
    treasure 트레저
    break 브레잌
    breaking 브레이킹
    great 그레잇
    wear 웨어
    swear 스웨어
    hear 히어
    hearing 히어링
    near 니어
    dear 디어
    clear 클리어
    fear 피어
    year 이어
    years 이어즈
    early 얼리
    learn 런
    learning 러닝
    heard 허드
    search 써치
    searching 써칭
    women 위민
    human 휴먼
    moment 모먼트
    minute 미닛
    minutes 미닛츠
    hour 아워
    hours 아워즈
    flower 플라워
    flowers 플라워즈
    shower 샤워
    our 아워
    door 도어
    floor 플로어
    poor 푸어
    sure 슈어
    pure 퓨어
    desire 디자이어
    tired 타이어드
    quiet 콰이엇
    silence 싸일런스
    silent 싸일런트
    island 아일랜드
    sign 싸인
    fine 파인
    line 라인
    wine 와인
    divine 디바인
    forgive 포기브
    calm 캄
    half 해프
    would 우드
    could 쿠드
    should 슈드
    put 풋
    putting 푸링
    push 푸쉬
    pushing 푸슁
    wish 위쉬
    wishing 위슁
    fish 피쉬
    rush 러쉬
    crush 크러쉬
    crash 크래쉬
    flash 플래쉬
    wash 워쉬
    fresh 프레쉬
    pull 풀
    pulling 풀링
    full 풀
    stood 스투드
    foot 풋
    book 북
    look 룩
    looking 루킹
    took 툭
    shook 슉
    school 스쿨
    rule 룰
    rules 룰즈
    issue 이쓔
    view 뷰
    few 퓨
    knew 뉴
    flew 플루
    grew 그루
    threw 쓰루
    throw 쓰로
    throwing 쓰로잉
    champagne 샴페인
    machine 머신
    gasoline 개솔린
    other 아더
    another 어나더
    mother 마더
    brother 브라더
    father 파더
    sister 씨스터
    better 베러
    letter 레러
    matter 매러
    butter 버러
    bitter 비러
    glitter 글리러
    shatter 섀러
    bottom 바럼
    summer 써머
    winter 윈터
    spring 스프링
    autumn 오럼
    city 씨리
    pity 피리
    duty 듀리
    dirty 더리
    shorty 쇼리
    shawty 쇼리
    danger 데인저
    dangerous 데인저러스
    do 두
    does 더즈
    did 디드
    doing 두잉
    watch 와치
    watching 와칭
    catch 캐치
    catching 캐칭
    bring 브링
    set 쎗
    setting 쎄링
    alight 얼라잇
    fantasy 판타지
    reality 리얼리리
    got 갓
    get 겟
    getting 게링
    hit 힛
    hitting 히링
    cut 컷
    cutting 커링
    shut 셧
    shutting 셔링
    shit 쉣
    magnet 매그넷
    shape 쉐입
    type 타입
    keep 킵
    keeping 키핑
    deep 딥
    step 스텝
    drop 드랍
    dropping 드라핑
    top 탑
    pop 팝
    lot 랏
    shot 샷
    spot 스팟
    clock 클락
    block 블락
    lock 락
    knock 낙
    shock 샥
    pocket 파켓
    rocket 라켓
    problem 프라블럼
    promise 프라미스
    follow 팔로우
    tomorrow 투마로우
    dollar 달러
    doctor 닥터
    special 스페셜
    """
}
