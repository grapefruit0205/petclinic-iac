function handler(event) {
    var uri = event.request.uri;
    // WAR 메뉴의 HOME/로고는 /petclinic/ 으로 간다 → S3 랜딩(/)으로 돌린다.
    // 302(임시)라서 나중에 리디자인 WAR 를 배포하면 함수만 떼면 원래대로 돌아온다.
    if (uri === '/petclinic' || uri === '/petclinic/') {
        return {
            statusCode: 302,
            statusDescription: 'Found',
            headers: { location: { value: '/' } }
        };
    }
    return event.request;
}