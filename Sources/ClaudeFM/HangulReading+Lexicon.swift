import Foundation

/// 영어 읽기 사전. 한 줄에 `낱말 읽기`, 구절 사전의 `_` 는 띄어쓰기다.
/// 받침은 ㄱㄴㄹㅁㅂㅅㅇ 만 쓰고, 긴 모음 뒤 k·p 는 크·프 (make -> 메이크), t 는 ㅅ (night -> 나잇) 으로 적는다.
extension HangulReading {
    static let phraseLexiconTable = """
    not at all 나래롤
    at all 애롤
    it all 이롤
    that all 대롤
    for all 포올
    after all 애프터롤
    thank you 땡큐
    thank u 땡큐
    thank ya 땡큐
    what's up 왓썹
    whats up 왓썹
    cheer up 치얼업
    rock and roll 락앤롤
    rock n roll 락앤롤
    rock 'n' roll 락앤롤
    rock n' roll 락앤롤
    hip hop 힙합
    ice cream 아이스크림
    new york 뉴욕
    las vegas 라스베이거스
    los angeles 로스앤젤레스
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
    got ya 가챠
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
    supposed to 써포스투
    trying to 트라이너
    out of 아우러브
    kind of 카인더
    sort of 쏘러
    lot of 라러
    lots of 라처브
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
    each of 이처브
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
    push it 푸쉿
    wish it 위쉿
    worth it 워씻
    with it 위딧
    in it 이닛
    on it 오닛
    is it 이짓
    was it 워짓
    does it 더짓
    come on 커몬
    hold on 홀돈
    move on 무본
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
    fold up 폴덥
    pull up 풀럽
    fill up 필럽
    call up 콜럽
    roll up 롤럽
    turn up 터넙
    burn up 버넙
    open up 오프넙
    clean up 클리넙
    run up 러넙
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
    watch out 와차웃
    reach out 리차웃
    stretch out 스트레차웃
    catch out 캐차웃
    wash out 워샤웃
    push out 푸샤웃
    rush out 러샤웃
    crash out 크래샤웃
    pass out 패싸웃
    miss out 미싸웃
    cross out 크로싸웃
    figure out 피겨라웃
    look at 루캣
    back at 배캣
    laugh at 래팻
    want it 워닛
    want a 워너
    le sserafim 르세라핌
    fell in 펠린
    right now 라잇_나우
    good night 굿나잇
    all right 올라잇
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
    an 언
    the 더
    i 아이
    u 유
    o 오
    me 미
    my 마이
    mine 마인
    myself 마이셀프
    you 유
    ya 야
    your 유어
    yours 유어즈
    yourself 유어셀프
    yourselves 유어셀브즈
    he 히
    him 힘
    his 히즈
    himself 힘셀프
    she 쉬
    her 허
    hers 허즈
    herself 허셀프
    it 잇
    its 잇츠
    itself 잇셀프
    we 위
    us 어스
    our 아워
    ours 아워즈
    ourselves 아워셀브즈
    they 데이
    them 뎀
    their 데어
    theirs 데어즈
    themselves 뎀셀브즈
    this 디스
    that 댓
    these 디즈
    those 도즈
    who 후
    whom 훔
    whose 후즈
    whoever 후에버
    whole 홀
    what 왓
    which 위치
    where 웨어
    when 웬
    why 와이
    how 하우
    whatever 와레버
    whenever 웨네버
    wherever 웨어레버
    however 하우에버
    and 앤
    or 오어
    but 벗
    so 쏘
    if 이프
    then 덴
    than 댄
    as 애즈
    at 앳
    by 바이
    for 포
    from 프럼
    in 인
    into 인투
    of 어브
    off 오프
    on 온
    onto 온투
    out 아웃
    over 오버
    to 투
    too 투
    up 업
    upon 어판
    with 위드
    within 위딘
    without 위다웃
    about 어바웃
    above 어버브
    across 어크로스
    after 애프터
    again 어게인
    against 어게인스트
    ago 어고
    along 얼롱
    alone 얼론
    among 어멍
    around 어라운드
    away 어웨이
    before 비포어
    behind 비하인드
    below 빌로우
    beneath 비니쓰
    beside 비싸이드
    between 비트윈
    beyond 비욘드
    down 다운
    during 듀링
    except 익셉트
    inside 인싸이드
    outside 아웃싸이드
    upside 업싸이드
    downside 다운싸이드
    near 니어
    past 패스트
    since 씬스
    through 쓰루
    throughout 쓰루아웃
    till 틸
    til 틸
    'til 틸
    until 언틸
    toward 투워드
    towards 투워즈
    under 언더
    underneath 언더니쓰
    is 이즈
    am 앰
    are 아
    was 워즈
    were 워
    be 비
    been 빈
    being 비잉
    do 두
    does 더즈
    did 디드
    done 던
    doing 두잉
    have 해브
    has 해즈
    had 해드
    having 해빙
    will 윌
    would 우드
    shall 쉘
    should 슈드
    can 캔
    could 쿠드
    may 메이
    might 마잇
    must 머스트
    ought 오트
    not 낫
    no 노
    yes 예스
    yeah 예
    yea 예
    yeh 예
    yep 옙
    nope 놉
    nah 나
    all 올
    any 애니
    some 썸
    every 에브리
    each 이치
    both 보쓰
    either 이더
    neither 니더
    none 넌
    one 원
    other 아더
    another 어나더
    such 써치
    same 쎄임
    own 오운
    only 온리
    just 저스트
    even 이븐
    ever 에버
    never 네버
    always 올웨이즈
    often 오픈
    still 스틸
    yet 옛
    already 올레디
    also 올쏘
    almost 올모스트
    very 베리
    really 리얼리
    quite 콰잇
    much 머치
    many 메니
    more 모어
    most 모스트
    less 레스
    least 리스트
    few 퓨
    here 히어
    there 데어
    now 나우
    soon 쑨
    today 투데이
    tonight 투나잇
    tomorrow 투마로우
    yesterday 예스터데이
    once 원스
    twice 트와이스
    because 비커즈
    cause 커즈
    'cause 커즈
    cuz 커즈
    cos 커즈
    coz 커즈
    though 도우
    tho 도우
    although 올도우
    while 와일
    whether 웨더
    unless 언레스
    anyway 애니웨이
    anymore 애니모어
    maybe 메이비
    perhaps 퍼햅스
    please 플리즈
    thanks 땡스
    thank 땡크
    sorry 쏘리
    okay 오케이
    ok 오케이
    alright 올라잇
    i'm 아임
    im 아임
    i'll 아일
    i'd 아이드
    i've 아이브
    you're 유어
    youre 유어
    you'll 율
    you'd 유드
    you've 유브
    he's 히즈
    he'll 힐
    he'd 히드
    she's 쉬즈
    she'll 쉴
    she'd 쉬드
    it's 잇츠
    it'll 이를
    it'd 이러드
    we're 위어
    we'll 윌
    we'd 위드
    we've 위브
    they're 데어
    theyre 데어
    they'll 데일
    they'd 데이드
    they've 데이브
    that's 댓츠
    thats 댓츠
    that'll 대를
    what's 왓츠
    whats 왓츠
    who's 후즈
    where's 웨어즈
    how's 하우즈
    there's 데어즈
    here's 히어즈
    let's 레츠
    lets 레츠
    don't 돈트
    dont 돈트
    doesn't 더즌트
    doesnt 더즌트
    didn't 디든트
    didnt 디든트
    can't 캔트
    cant 캔트
    couldn't 쿠든트
    couldnt 쿠든트
    won't 원트
    wont 원트
    wouldn't 우든트
    wouldnt 우든트
    shouldn't 슈든트
    shouldnt 슈든트
    isn't 이즌트
    isnt 이즌트
    aren't 안트
    arent 안트
    wasn't 워즌트
    wasnt 워즌트
    weren't 원트
    werent 원트
    haven't 해븐트
    havent 해븐트
    hasn't 해즌트
    hasnt 해즌트
    hadn't 해든트
    hadnt 해든트
    ain't 에인트
    aint 에인트
    mustn't 머슨트
    could've 쿠더브
    should've 슈더브
    would've 우더브
    might've 마이러브
    must've 머스터브
    y'all 요올
    yall 요올
    ma'am 맴
    o'clock 어클락
    c'mon 커몬
    'em 엄
    'bout 바웃
    bout 바웃
    'round 라운드
    gonna 거너
    wanna 워너
    gotta 가러
    kinda 카인더
    sorta 쏘러
    outta 아우러
    lotta 라러
    oughta 오러
    hafta 해프터
    coulda 쿠더
    woulda 우더
    shoulda 슈더
    musta 머스터
    gotcha 가차
    betcha 베처
    whatcha 와처
    lemme 레미
    gimme 기미
    dunno 더노
    tryna 트라이너
    imma 아이머
    i'mma 아이머
    finna 피나
    lil 릴
    luv 러브
    thru 쓰루
    nite 나잇
    tonite 투나잇
    nothin 너씬
    somethin 썸씬
    goin 고인
    oh 오
    ohh 오
    ooh 우
    oooh 우
    ah 아
    ahh 아
    aah 아
    uh 어
    uhh 어
    um 엄
    umm 엄
    hmm 흠
    hm 흠
    mm 음
    mmm 음
    mhm 음흠
    huh 허
    woah 워
    whoa 워
    wow 와우
    yay 예이
    yo 요
    hey 헤이
    hi 하이
    hello 헬로
    bye 바이
    goodbye 굿바이
    ha 하
    haha 하하
    hahaha 하하하
    la 라
    na 나
    da 다
    ba 바
    doo 두
    dum 덤
    dee 디
    ay 아이
    ayy 에이
    ayo 에이오
    eh 에
    oops 웁스
    ouch 아우치
    aww 오
    woo 우
    whoo 후
    yahoo 야후
    hooray 후레이
    amen 아멘
    hallelujah 할렐루야
    shh 쉿
    psst 프스트
    uh-huh 어허
    uh-oh 어오
    mm-hmm 음흠
    a-ha 아하
    aha 아하
    ugh 어그
    bang 뱅
    boom 붐
    pow 파우
    bling 블링
    yum 염
    yummy 여미
    skrrt 스커트
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
    twelfth 트웰프쓰
    percent 퍼센트
    point 포인트
    number 넘버
    half 해프
    double 더블
    single 씽글
    dozen 더즌
    time 타임
    day 데이
    night 나잇
    morning 모닝
    evening 이브닝
    afternoon 애프터눈
    midnight 미드나잇
    week 위크
    weekend 위켄드
    month 먼쓰
    year 이어
    moment 모먼트
    minute 미닛
    hour 아워
    forever 포레버
    forevermore 포레버모어
    sunday 썬데이
    monday 먼데이
    tuesday 튜즈데이
    wednesday 웬즈데이
    thursday 써스데이
    friday 프라이데이
    saturday 쌔러데이
    january 재뉴어리
    february 페브러리
    march 마치
    april 에이프릴
    june 준
    july 줄라이
    august 오거스트
    september 쎕템버
    october 악토버
    november 노벰버
    december 디셈버
    spring 스프링
    summer 써머
    autumn 오럼
    winter 윈터
    season 씨즌
    christmas 크리스마스
    xmas 크리스마스
    birthday 버쓰데이
    holiday 할러데이
    valentine 밸런타인
    halloween 핼러윈
    dawn 돈
    clock 클락
    calendar 캘린더
    history 히스토리
    future 퓨처
    present 프레즌트
    century 쎈추리
    decade 데케이드
    someday 썸데이
    sometime 썸타임
    sometimes 썸타임즈
    body 바디
    heart 하트
    soul 쏘울
    mind 마인드
    head 헤드
    face 페이스
    eye 아이
    eyes 아이즈
    lip 립
    mouth 마우쓰
    tongue 텅
    teeth 티쓰
    tooth 투쓰
    nose 노즈
    ear 이어
    hair 헤어
    skin 스킨
    hand 핸드
    finger 핑거
    arm 암
    shoulder 숄더
    chest 체스트
    leg 레그
    knee 니
    foot 풋
    feet 핏
    blood 블러드
    bone 본
    breath 브레쓰
    breathe 브리드
    breathing 브리딩
    voice 보이스
    tear 티어
    tears 티어즈
    sweat 스웻
    pulse 펄스
    brain 브레인
    waist 웨이스트
    neck 넥
    cheek 치크
    smile 스마일
    kiss 키스
    touch 터치
    hug 허그
    love 러브
    loved 러브드
    loving 러빙
    lover 러버
    lovely 러블리
    baby 베이비
    babe 베이브
    darling 달링
    honey 허니
    sweetheart 스윗하트
    sugar 슈거
    angel 에인절
    dear 디어
    crush 크러쉬
    feel 필
    feeling 필링
    emotion 이모션
    passion 패션
    desire 디자이어
    romance 로맨스
    happy 해피
    sad 쌔드
    mad 매드
    lonely 론리
    pain 페인
    hurt 허트
    cry 크라이
    crying 크라잉
    laugh 래프
    fear 피어
    afraid 어프레이드
    crazy 크레이지
    insane 인쎄인
    wild 와일드
    free 프리
    freedom 프리덤
    jealous 젤러스
    jealousy 젤러시
    anger 앵거
    angry 앵그리
    hungry 헝그리
    miss 미스
    missing 미씽
    need 니드
    want 원트
    wanted 워니드
    wanting 원팅
    wish 위쉬
    wishing 위슁
    hope 호프
    hopeless 호플리스
    dream 드림
    dreaming 드리밍
    believe 빌리브
    believing 빌리빙
    trust 트러스트
    faith 페이쓰
    promise 프라미스
    together 투게더
    apart 어파트
    broken 브로큰
    heartbreak 하트브레이크
    heartbeat 하트비트
    heartache 하트에이크
    tender 텐더
    gentle 젠틀
    kind 카인드
    sweet 스윗
    cute 큐트
    pretty 프리리
    beautiful 뷰리풀
    beauty 뷰리
    gorgeous 고저스
    handsome 핸썸
    sexy 쎅시
    sex 쎅스
    hot 핫
    cool 쿨
    nervous 너버스
    shy 샤이
    brave 브레이브
    strong 스트롱
    weak 위크
    proud 프라우드
    guilty 길티
    innocent 이노센트
    honest 아니스트
    true 트루
    truth 트루쓰
    lie 라이
    liar 라이어
    fake 페이크
    real 리얼
    reality 리얼리리
    perfect 퍼펙트
    special 스페셜
    magic 매직
    wonderful 원더풀
    amazing 어메이징
    awesome 오썸
    awful 오풀
    fantastic 팬태스틱
    fantasy 판타지
    incredible 인크레더블
    lucky 러키
    desperate 데스퍼릿
    selfish 쎌피쉬
    stupid 스투피드
    silly 씰리
    fool 풀
    idiot 이디엇
    genius 지니어스
    hero 히어로
    villain 빌런
    monster 몬스터
    devil 데빌
    demon 디먼
    ghost 고스트
    god 갓
    lord 로드
    heaven 헤븐
    hell 헬
    paradise 패러다이스
    spirit 스피릿
    destiny 데스티니
    fate 페잇
    luck 럭
    chance 챈스
    miracle 미러클
    mystery 미스터리
    secret 씨크릿
    memory 메모리
    world 월드
    earth 어쓰
    sky 스카이
    sun 썬
    sunny 써니
    moon 문
    star 스타
    cloud 클라우드
    rain 레인
    rainbow 레인보우
    snow 스노우
    storm 스톰
    thunder 썬더
    wind 윈드
    fire 파이어
    flame 플레임
    smoke 스모크
    water 워러
    ocean 오션
    river 리버
    lake 레이크
    wave 웨이브
    beach 비치
    island 아일랜드
    mountain 마운틴
    valley 밸리
    forest 포레스트
    tree 트리
    flower 플라워
    rose 로즈
    garden 가든
    stone 스톤
    rock 락
    ice 아이스
    gold 골드
    golden 골든
    silver 씰버
    diamond 다이아몬드
    crystal 크리스털
    pearl 펄
    light 라잇
    lighter 라이러
    lighting 라이링
    dark 다크
    shadow 섀도우
    universe 유니버스
    galaxy 갤럭시
    planet 플래닛
    space 스페이스
    nature 네이처
    animal 애니멀
    bird 버드
    butterfly 버터플라이
    wolf 울프
    lion 라이언
    tiger 타이거
    bear 베어
    fish 피쉬
    dragon 드래곤
    unicorn 유니콘
    cherry 체리
    apple 애플
    peach 피치
    banana 바나나
    lemon 레몬
    orange 오렌지
    chocolate 초콜릿
    candy 캔디
    cake 케이크
    cookie 쿠키
    coffee 커피
    wine 와인
    champagne 샴페인
    whiskey 위스키
    vodka 보드카
    tequila 데킬라
    beer 비어
    milk 밀크
    juice 주스
    city 씨리
    town 타운
    street 스트릿
    road 로드
    home 홈
    house 하우스
    houses 하우지즈
    room 룸
    bed 베드
    door 도어
    window 윈도우
    wall 월
    floor 플로어
    party 파리
    club 클럽
    school 스쿨
    church 처치
    country 컨트리
    people 피플
    person 퍼슨
    man 맨
    men 멘
    woman 우먼
    women 위민
    boy 보이
    girl 걸
    kid 키드
    child 차일드
    children 칠드런
    lady 레이디
    gentleman 젠틀맨
    king 킹
    queen 퀸
    prince 프린스
    princess 프린세스
    friend 프렌드
    family 패밀리
    mother 마더
    mom 맘
    mama 마마
    mommy 마미
    father 파더
    dad 대드
    daddy 대디
    papa 파파
    brother 브라더
    sister 씨스터
    son 썬
    daughter 도러
    wife 와이프
    husband 허즈번드
    stranger 스트레인저
    enemy 에너미
    idol 아이돌
    fan 팬
    singer 씽어
    killer 킬러
    rider 라이더
    soldier 솔저
    doctor 닥터
    teacher 티처
    go 고
    goes 고즈
    went 웬트
    gone 곤
    come 컴
    came 케임
    coming 커밍
    become 비컴
    became 비케임
    get 겟
    got 갓
    gotten 가튼
    getting 게링
    give 기브
    gave 게이브
    given 기븐
    giving 기빙
    forgive 포기브
    forgave 포게이브
    forgiven 포기븐
    unforgiven 언포기븐
    take 테이크
    taking 테이킹
    took 툭
    taken 테이큰
    mistake 미스테이크
    make 메이크
    making 메이킹
    made 메이드
    wake 웨이크
    waking 웨이킹
    woke 워크
    shake 쉐이크
    shaking 쉐이킹
    shook 슉
    break 브레이크
    breaking 브레이킹
    broke 브로크
    like 라이크
    know 노
    knew 뉴
    known 노운
    knowing 노잉
    see 씨
    saw 쏘
    seen 씬
    say 쎄이
    says 쎄즈
    said 쎄드
    tell 텔
    told 톨드
    think 띵크
    thinking 띵킹
    thought 쏘트
    felt 펠트
    find 파인드
    found 파운드
    lose 루즈
    losing 루징
    lost 로스트
    win 윈
    won 원
    fall 폴
    fell 펠
    fallen 폴른
    run 런
    ran 랜
    fly 플라이
    flew 플루
    drive 드라이브
    drove 드로브
    driven 드리븐
    ride 라이드
    rode 로드
    write 라잇
    wrote 로트
    written 리튼
    speak 스피크
    spoke 스포크
    steal 스틸
    stole 스톨
    choose 추즈
    chose 초즈
    chosen 초즌
    freeze 프리즈
    froze 프로즈
    frozen 프로즌
    shine 샤인
    shining 샤이닝
    sing 씽
    sang 쌩
    sung 썽
    ring 링
    rang 랭
    swim 스윔
    swam 스왬
    drink 드링크
    drank 드랭크
    drunk 드렁크
    begin 비긴
    beginning 비기닝
    began 비갠
    begun 비건
    forget 포겟
    forgot 포갓
    forgotten 포가튼
    hide 하이드
    hid 히드
    hidden 히든
    hold 홀드
    holding 홀딩
    held 헬드
    keep 킵
    kept 켑트
    sleep 슬립
    slept 슬렙트
    leave 리브
    left 레프트
    meet 밋
    met 멧
    bring 브링
    brought 브로트
    buy 바이
    bought 보트
    catch 캐치
    caught 코트
    teach 티치
    taught 토트
    fight 파잇
    fighting 파이링
    fought 포트
    seek 씨크
    sought 쏘트
    build 빌드
    built 빌트
    send 쎈드
    sent 쎈트
    burn 번
    burning 버닝
    learn 런
    learning 러닝
    mean 민
    meant 멘트
    read 리드
    lead 리드
    led 레드
    hear 히어
    hearing 히어링
    heard 허드
    stand 스탠드
    stood 스투드
    understand 언더스탠드
    understood 언더스투드
    sit 씻
    sat 쌧
    sitting 씨링
    lay 레이
    pay 페이
    paid 페이드
    sell 쎌
    sold 쏠드
    wear 웨어
    wore 워어
    worn 원
    swear 스웨어
    throw 쓰로우
    threw 쓰루
    blow 블로우
    blew 블루
    grow 그로우
    grew 그루
    slow 슬로우
    low 로우
    show 쇼
    draw 드로
    put 풋
    cut 컷
    hit 힛
    let 렛
    set 쎗
    shut 셧
    cost 코스트
    quit 큇
    bet 벳
    beat 비트
    eat 잇
    ate 에잇
    eaten 이튼
    try 트라이
    die 다이
    dying 다잉
    kill 킬
    live 리브
    living 리빙
    lived 리브드
    hate 헤잇
    wait 웨잇
    waiting 웨이링
    stay 스테이
    stop 스탑
    start 스타트
    turn 턴
    move 무브
    moving 무빙
    prove 프루브
    remove 리무브
    dance 댄스
    dancing 댄싱
    play 플레이
    playing 플레잉
    work 워크
    firework 파이어워크
    call 콜
    calling 콜링
    ask 애스크
    answer 앤서
    look 룩
    looking 루킹
    watch 와치
    watching 와칭
    wash 워쉬
    washing 워슁
    listen 리슨
    talk 토크
    talking 토킹
    walk 워크
    walking 워킹
    jump 점프
    push 푸쉬
    pushing 푸슁
    pull 풀
    pulling 풀링
    open 오픈
    close 클로스
    closed 클로즈드
    save 쎄이브
    saving 쎄이빙
    change 체인지
    changing 체인징
    exchange 익스체인지
    arrange 어레인지
    follow 팔로우
    remember 리멤버
    imagine 이매진
    realize 리얼라이즈
    happen 해픈
    matter 매러
    care 케어
    worry 워리
    hurry 허리
    carry 캐리
    marry 매리
    married 매리드
    bury 베리
    study 스터디
    copy 카피
    envy 엔비
    wonder 원더
    wondering 원더링
    search 써치
    searching 써칭
    roll 롤
    rolling 롤링
    rule 룰
    good 굿
    bad 배드
    better 베러
    best 베스트
    worse 워스
    worst 워스트
    big 빅
    bigger 비거
    biggest 비기스트
    small 스몰
    little 리를
    long 롱
    short 쇼트
    high 하이
    higher 하이어
    cold 콜드
    warm 웜
    new 뉴
    news 뉴스
    old 올드
    young 영
    fast 패스트
    easy 이지
    hard 하드
    soft 쏘프트
    loud 라우드
    quiet 콰이엇
    bright 브라잇
    deep 딥
    full 풀
    empty 엠티
    rich 리치
    poor 푸어
    bitter 비러
    sour 싸워
    fresh 프레쉬
    clean 클린
    dirty 더리
    alive 얼라이브
    dead 데드
    death 데쓰
    safe 쎄이프
    danger 데인저
    dangerous 데인저러스
    strange 스트레인지
    weird 위어드
    funny 퍼니
    serious 씨리어스
    famous 페이머스
    ugly 어글리
    simple 씸플
    sure 슈어
    ready 레디
    busy 비지
    lazy 레이지
    tired 타이어드
    sick 씩
    holy 홀리
    blue 블루
    red 레드
    green 그린
    yellow 옐로우
    black 블랙
    white 와잇
    pink 핑크
    purple 퍼플
    gray 그레이
    grey 그레이
    brown 브라운
    neon 네온
    electric 일렉트릭
    final 파이널
    metal 메탈
    mental 멘탈
    royal 로열
    loyal 로열
    cruel 크루얼
    precious 프레셔스
    delicious 딜리셔스
    curious 큐리어스
    music 뮤직
    song 쏭
    melody 멜로디
    rhythm 리듬
    bass 베이스
    drum 드럼
    guitar 기타
    piano 피아노
    radio 라디오
    stereo 스테레오
    speaker 스피커
    microphone 마이크로폰
    mic 마이크
    stage 스테이지
    concert 콘서트
    tour 투어
    vibe 바이브
    groove 그루브
    mood 무드
    flow 플로우
    rap 랩
    rapper 래퍼
    pop 팝
    jazz 재즈
    blues 블루즈
    funk 펑크
    disco 디스코
    techno 테크노
    lyrics 리릭스
    chorus 코러스
    encore 앙코르
    camera 카메라
    video 비디오
    movie 무비
    film 필름
    picture 픽처
    photo 포토
    selfie 쎌피
    phone 폰
    message 메시지
    internet 인터넷
    online 온라인
    website 웹사이트
    email 이메일
    computer 컴퓨러
    laptop 랩탑
    app 앱
    game 게임
    youtube 유튜브
    instagram 인스타그램
    iphone 아이폰
    netflix 넷플릭스
    google 구글
    tiktok 틱톡
    twitter 트위러
    emoji 이모지
    wifi 와이파이
    user 유저
    tech 테크
    technology 테크놀로지
    life 라이프
    thing 띵
    something 썸씽
    nothing 너씽
    anything 애니씽
    everything 에브리씽
    everyone 에브리원
    everybody 에브리바디
    someone 썸원
    somebody 썸바디
    anyone 애니원
    anybody 애니바디
    nobody 노바디
    somewhere 썸웨어
    nowhere 노웨어
    money 머니
    cash 캐쉬
    dollar 달러
    price 프라이스
    gift 기프트
    car 카
    train 트레인
    key 키
    monkey 멍키
    journey 저니
    story 스토리
    word 워드
    name 네임
    line 라인
    sign 싸인
    letter 레러
    paper 페이퍼
    color 컬러
    colour 컬러
    shape 쉐이프
    type 타입
    hype 하입
    size 싸이즈
    dress 드레스
    shirt 셔츠
    t-shirt 티셔츠
    shoe 슈
    shoes 슈즈
    jeans 진즈
    jacket 재킷
    necklace 네클리스
    crown 크라운
    mirror 미러
    glass 글래스
    bottle 바를
    battle 배를
    settle 쎄를
    table 테이블
    pillow 필로우
    blanket 블랭킷
    candle 캔들
    gun 건
    bullet 불릿
    knife 나이프
    sword 쏘드
    war 워
    peace 피스
    army 아미
    law 로
    power 파워
    energy 에너지
    problem 프라블럼
    question 퀘스천
    reason 리즌
    sense 쎈스
    idea 아이디어
    choice 초이스
    decision 디시전
    lesson 레슨
    goal 골
    adventure 어드벤처
    place 플레이스
    side 싸이드
    top 탑
    bottom 바럼
    edge 엣지
    end 엔드
    middle 미들
    center 쎈터
    corner 코너
    circle 써클
    level 레벨
    step 스텝
    drop 드랍
    lot 랏
    shot 샷
    spot 스팟
    block 블락
    lock 락
    knock 낙
    shock 샥
    pocket 포켓
    rocket 로켓
    ticket 티켓
    market 마켓
    jewel 쥬얼
    jewelry 쥬얼리
    issue 이쓔
    view 뷰
    machine 머신
    gasoline 개솔린
    routine 루틴
    magazine 매거진
    engine 엔진
    medicine 메디슨
    genuine 제뉴인
    super 슈퍼
    superstar 슈퍼스타
    superman 슈퍼맨
    spiderman 스파이더맨
    batman 배트맨
    spider 스파이더
    hydromatic 하이드로매틱
    automatic 오토매틱
    systematic 씨스테매틱
    criminal 크리미널
    smooth 스무드
    enough 이너프
    tough 터프
    rough 러프
    cough 코프
    worth 워쓰
    both 보쓰
    youth 유쓰
    south 싸우쓰
    north 노쓰
    church 처치
    worship 워쉽
    dog 도그
    cat 캣
    glance 글랜스
    oughta 오러
    above 어버브
    glove 글러브
    dove 더브
    shove 셔브
    some 썸
    welcome 웰컴
    awesome 오썸
    lonesome 론썸
    front 프런트
    blood 블러드
    flood 플러드
    trouble 트러블
    couple 커플
    cousin 커즌
    ocean 오션
    vision 비전
    island 아일랜드
    instead 인스테드
    weather 웨더
    pleasure 플레저
    treasure 트레저
    great 그레잇
    clear 클리어
    early 얼리
    women 위민
    human 휴먼
    pure 퓨어
    desire 디자이어
    silence 싸일런스
    silent 싸일런트
    fine 파인
    divine 디바인
    calm 캄
    palm 팜
    shoot 슛
    stood 스투드
    wood 우드
    good 굿
    book 북
    school 스쿨
    view 뷰
    flew 플루
    other 아더
    sorry 쏘리
    hello 헬로
    yesterday 예스터데이
    seoul 서울
    korea 코리아
    korean 코리안
    japan 재팬
    china 차이나
    tokyo 도쿄
    paris 패리스
    london 런던
    hollywood 할리우드
    california 캘리포니아
    miami 마이애미
    vegas 베이거스
    texas 텍사스
    mexico 멕시코
    brooklyn 브루클린
    manhattan 맨해튼
    america 아메리카
    american 아메리칸
    africa 아프리카
    europe 유럽
    asia 아시아
    egypt 이집트
    rome 롬
    italy 이탈리
    france 프랜스
    venice 베니스
    hawaii 하와이
    georgia 조지아
    chicago 시카고
    atlanta 애틀랜타
    brazil 브라질
    havana 하바나
    india 인디아
    jesus 지저스
    christ 크라이스트
    mary 메리
    maria 마리아
    romeo 로미오
    juliet 줄리엣
    john 존
    johnny 조니
    michael 마이클
    david 데이빗
    james 제임스
    jack 잭
    billie 빌리
    jean 진
    peter 피터
    paul 폴
    george 조지
    harry 해리
    tom 톰
    sam 쌤
    alex 알렉스
    sarah 사라
    emily 에밀리
    jennifer 제니퍼
    jessica 제시카
    amanda 어맨다
    rebecca 레베카
    elizabeth 엘리자베스
    victoria 빅토리아
    diana 다이애나
    sophia 소피아
    olivia 올리비아
    emma 엠마
    lucy 루시
    lily 릴리
    rosie 로지
    jenny 제니
    annie 애니
    kelly 켈리
    lisa 리사
    jennie 제니
    jisoo 지수
    rosé 로제
    taylor 테일러
    justin 저스틴
    ariana 아리아나
    selena 셀레나
    katy 케이티
    gaga 가가
    beyonce 비욘세
    beyoncé 비욘세
    rihanna 리한나
    drake 드레이크
    eminem 에미넴
    adele 아델
    madonna 마돈나
    britney 브리트니
    elvis 엘비스
    bruno 브루노
    cinderella 신데렐라
    alice 앨리스
    aespa 에스파
    newjeans 뉴진스
    shinee 샤이니
    blink 블링크
    army 아미
    psycho 사이코
    likey 라이키
    ddu-du 뚜두
    peek-a-boo 피카부
    dalla 달라
    ditto 디토
    rock'n'roll 락앤롤
    rock-n-roll 락앤롤
    twilight 트와일라잇
    dynamite 다이너마잇
    vacation 베이케이션
    destination 데스티네이션
    reaction 리액션
    create 크리에잇
    creative 크리에이티브
    creature 크리처
    private 프라이빗
    climate 클라이밋
    favorite 페이버릿
    definitely 데피니틀리
    immediately 이미디어틀리
    ultimate 얼티밋
    intimate 인티밋
    negative 네거티브
    olive 올리브
    advice 어드바이스
    device 디바이스
    sacrifice 쌔크리파이스
    excellent 엑설런트
    exercise 엑서사이즈
    extra 엑스트라
    exit 엑싯
    escape 이스케이프
    whistle 휘슬
    climb 클라임
    tiger 타이거
    eager 이거
    burger 버거
    target 타깃
    clever 클레버
    cover 커버
    shiver 쉬버
    liver 리버
    deliver 딜리버
    honor 아너
    period 피리어드
    zero 제로
    series 시리즈
    theory 씨어리
    theater 씨어러
    area 에어리어
    parent 페어런트
    various 베리어스
    salad 쌜러드
    data 데이터
    canada 캐나다
    event 이벤트
    prevent 프리벤트
    invent 인벤트
    content 콘텐트
    cement 씨멘트
    comment 코멘트
    request 리퀘스트
    suggest 써제스트
    arrest 어레스트
    regard 리가드
    sweat 스웻
    threat 쓰렛
    quality 퀄리티
    function 펑션
    anxious 앵셔스
    language 랭귀지
    average 애버리지
    allow 얼라우
    cow 카우
    bow 보우
    bowl 보울
    fallen 폴른
    control 컨트롤
    patrol 퍼트롤
    honest 아니스트
    modern 모던
    toxic 탁식
    comic 코믹
    lyric 리릭
    rhyme 라임
    friend 프렌드
    science 싸이언스
    client 클라이언트
    giant 자이언트
    violent 바이얼런트
    violin 바이올린
    pilot 파일럿
    final 파이널
    rival 라이벌
    rebel 레블
    title 타이틀
    item 아이템
    iron 아이언
    irish 아이리시
    virus 바이러스
    siren 사이렌
    pirate 파이럿
    rising 라이징
    galaxy 갤럭시
    savage 쌔비지
    image 이미지
    chaos 케이오스
    echo 에코
    ache 에이크
    stomach 스터머크
    character 캐릭터
    chemistry 케미스트리
    orchestra 오케스트라
    anchor 앵커
    choir 콰이어
    chef 셰프
    chic 시크
    champagne 샴페인
    machine 머신
    ballet 발레
    cafe 카페
    café 카페
    resume 레주메
    recipe 레시피
    karaoke 가라오케
    bag 백
    mask 마스크
    emotional 이모셔널
    everlasting 에버래스팅
    exhaust 이그조스트
    exhausted 이그조스티드
    passionate 패셔닛
    delicate 델리킷
    unconditional 언컨디셔널
    vibrant 바이브런트
    ginger 진저
    basically 베이시컬리
    y'know 야노
    boo 부
    fun 펀
    teenage 틴에이지
    n 앤
    'n' 앤
    n' 앤
    'n 앤
    boombayah 붐바야
    lalisa 라리사
    alcohol 알코올
    scientist 싸이언티스트
    armageddon 아마게돈
    kitsch 키치
    record 레코드
    venom 베놈
    use 유즈
    used 유즈드
    uses 유지즈
    useful 유스풀
    useless 유슬리스
    enchant 인챈트
    enchanted 인챈티드
    sound 싸운드
    suck 썩
    right 라잇
    back 백
    way 웨이
    sight 싸잇
    tight 타잇
    flight 플라잇
    late 레잇
    later 레이러
    state 스테잇
    date 데잇
    gate 게잇
    heavy 헤비
    shower 샤워
    rush 러쉬
    crash 크래쉬
    flash 플래쉬
    butter 버러
    glitter 글리러
    shatter 섀러
    pity 피리
    duty 듀리
    shorty 쇼리
    shawty 쇼리
    alight 얼라잇
    shit 쉣
    magnet 매그넷
    alien 에일리언
    alibi 앨러바이
    anxiety 앵자이어티
    ballad 발라드
    balloon 벌룬
    bracelet 브레이슬릿
    chemical 케미컬
    clothes 클로즈
    collide 컬라이드
    comfortable 컴퍼터블
    ecstasy 엑스터시
    elevator 엘리베이터
    evil 이블
    excite 익싸잇
    fortune 포춘
    freak 프릭
    halo 헤일로
    heartless 하트리스
    horizon 호라이즌
    innocence 이노센스
    laughter 래프터
    legend 레전드
    lollipop 롤리팝
    lullaby 럴러바이
    luxury 럭셔리
    masquerade 매스커레이드
    museum 뮤지엄
    naked 네이키드
    nostalgia 노스탤지어
    obsessed 업세스트
    obsession 업세션
    obvious 아비어스
    omen 오멘
    palace 팰리스
    parade 퍼레이드
    passenger 패신저
    recover 리커버
    discover 디스커버
    cover 커버
    release 릴리스
    remedy 레머디
    rescue 레스큐
    roulette 룰렛
    sacred 쎄이크리드
    safety 쎄이프티
    sea 씨
    silhouette 실루엣
    spiral 스파이럴
    suicide 수어사이드
    tattoo 타투
    tornado 토네이도
    trauma 트라우마
    tsunami 쓰나미
    vitamin 비타민
    vow 바우
    waste 웨이스트
    wicked 위키드
    wisdom 위즈덤
    wolves 울브즈
    wound 운드
    xoxo 엑스오엑스오
    zombie 좀비
    apply 어플라이
    disappear 디써피어
    """
}
