// 화면에 나오는 말, 한국어. ja.ts 와 같은 키를 모두 가지고 있어야
// 해요(Dict 타입). 일본어의 부드러운 말투에 맞추되, 쉼표는 일본어
// 読点처럼 많이 찍지 않고 한국어에서 자연스러운 만큼만. 부드러움은
// 딱딱한 합니다체가 아니라 따뜻한 해요체로 낸다.
import type { Dict } from './ja';

export const ko: Dict = {
  // ── 공통 ─────────────────────────────────────────────
  'common.loading': '읽고 있어요…',
  'common.loadMore': '더 보기',
  'common.backToTimeline': '타임라인으로 돌아가기',
  'common.timeline': '타임라인',
  'common.backToTop': '처음으로 돌아가기',
  'common.sending': '보내고 있어요…',
  'common.deliverFailed': '잘 닿지 않았어요.',
  'common.deliverFailedRetry': '잘 닿지 않았어요. 다시 한번 해볼까요?',
  'common.readFailed': '잘 읽지 못했어요.',
  'common.acctNotFound': '「@{acct}」님을 찾지 못했어요.',

  // ── 언어 전환 ────────────────────────────────────────
  'lang.switch': '언어 선택',

  // ── 타임라인 위 메뉴 ─────────────────────────────────
  'nav.notifications': '알림',
  'nav.messages': '메시지',
  'nav.bookmarks': '북마크',
  'nav.favourites': '즐겨찾기',
  'nav.lists': '리스트',
  'nav.search': '찾기',
  'nav.settings': '설정',
  'nav.compose': '쓰기',
  'nav.logout': '로그아웃',

  // ── 첫 페이지 ────────────────────────────────────────
  'landing.heroTitle': '여기는 조용한 Fediverse 의 집이에요.',
  'landing.tagline':
    '바로 옆에 살며시 앉아서 다른 사람의 이야기를 듣기도 하고, 가끔 자기 이야기를 하기도 하는 곳.',
  'landing.startTitle': '시작하기',
  'landing.startDesc': '초대 코드가 있으면 여기서 만들 수 있어요.',
  'landing.enterTitle': '들어가기',
  'landing.enterDesc': '이미 살고 있는 분은 이쪽에서.',
  'landing.about':
    'sukhi-fedi 는 ActivityPub 로 이야기하는 Fediverse 서버예요. Mastodon 이나 Misskey 와 이어져 있어요. 여기서 만든 계정으로 멀리 있는 사람의 말을 듣고, 가까이 있는 사람과 이야기할 수 있어요.',

  // ── 쓰는 곳 ──────────────────────────────────────────
  'compose.visPublic': '모두에게',
  'compose.visUnlisted': '모두에게 (타임라인에는 싣지 않고)',
  'compose.visPrivate': '팔로워에게만',
  'compose.visDirect': '지정한 사람에게만',
  'compose.uploadFailed': '이미지가 잘 올라가지 않았어요.',
  'compose.postFailed': '잘 보내지지 않았어요. 다시 한번 해볼까요?',
  'compose.reauth': '다시 한번 들어와 주세요.',
  'compose.replyTo': '@{acct} 님에게 답장',
  'compose.cancel': '그만두기',
  'compose.spoilerLabel': '먼저 보여줄 한마디 (접은 글의 겉면)',
  'compose.spoilerPlaceholder': '예: 졸린 이야기',
  'compose.bodyLabel': '본문',
  'compose.placeholderReply': '답장을 써요…',
  'compose.placeholderNew': '지금 떠오르는 생각…',
  'compose.removeMedia': '빼기',
  'compose.addImage': '이미지 더하기',
  'compose.fold': '접기',
  'compose.sensitive': '열람 주의',
  'compose.visLabel': '공개 범위',
  'compose.uploading': '올리고 있어요…',
  'compose.submit': '보내기',

  // ── 글(노트)──────────────────────────────────────────
  'status.boostedBy': '님이 부스트',
  'status.now': '방금',
  'status.minutesAgo': '{n}분 전',
  'status.hoursAgo': '{n}시간 전',
  'status.daysAgo': '{n}일 전',
  'status.tapToShow': '눌러서 보기',
  'status.imageZoom': '이미지 확대',
  'status.openAttachment': '첨부 파일 열기',
  'status.close': '닫기',
  'status.poll': '투표',
  'status.vote': '투표하기',
  'status.votes': '{n}표',
  'status.pollClosed': '・마감되었어요',
  'status.reactions': '반응',
  'status.favourite': '즐겨찾기',
  'status.boost': '부스트',
  'status.bookmarkAdd': '북마크',
  'status.bookmarkRemove': '북마크 빼기',
  'status.reply': '답장',
  'status.more': '다른 작업',
  'status.unpin': '고정 풀기',
  'status.pin': '고정하기',
  'status.delete': '삭제',
  'status.reported': '신고했어요',
  'status.report': '신고',
  'status.confirmDelete': '이 글을 삭제할까요? 이 작업은 되돌릴 수 없어요.',
  'status.reportPrompt': '신고 이유가 있으면 적어 주세요 (선택)',

  // ── 반응 고르기 ──────────────────────────────────────
  'reaction.pick': '반응 고르기',

  // ── 팔로우 버튼 ──────────────────────────────────────
  'follow.following': '팔로잉',
  'follow.requested': '승인 대기',
  'follow.follow': '팔로우',

  // ── 팔로우 목록 ──────────────────────────────────────
  'accountList.possFollowers': '의 팔로워',
  'accountList.possFollowing': '의 팔로잉',
  'accountList.empty': '아직 아무도 없어요.',

  // ── 새 버전 배너 ─────────────────────────────────────
  'update.available': '새로운 버전이 나왔어요.',
  'update.reload': '다시 읽기',
  'update.later': '나중에',

  // ── 설정 ─────────────────────────────────────────────
  'settings.title': '설정',
  'settings.displayName': '표시 이름',
  'settings.bio': '자기소개',
  'settings.avatarNew': '새 아이콘 (저장 전)',
  'settings.avatarNow': '지금 아이콘',
  'settings.headerNew': '새 헤더 이미지 (저장 전)',
  'settings.headerNow': '지금 헤더 이미지',
  'settings.locked': '팔로우를 승인한 뒤에 받기 (잠금)',
  'settings.saving': '저장하고 있어요…',
  'settings.save': '저장',
  'settings.saved': '저장했어요.',
  'settings.saveFailed': '잘 저장하지 못했어요.',
  'settings.blockMute': '차단・뮤트',
  'settings.blocking': '차단 중',
  'settings.muting': '뮤트 중',
  'settings.noneHere': '없어요.',
  'settings.release': '해제',
  'settings.admin': '관리',
  'settings.adminDesc': '이 인스턴스의 관리 페이지에 들어갈 수 있어요.',
  'settings.adminEnter': '관리 페이지로',
  'settings.language': '언어',
  'settings.changePassword': '비밀번호 변경',
  'settings.emojiCreditPre': '이모지는 ',
  'settings.emojiCreditParenOpen': ' (',
  'settings.emojiCreditParenClose': ').',

  // ── 시작하기(signup)──────────────────────────────────
  'signup.title': '시작하기',
  'signup.tagline': '초대 코드와 이름과 비밀번호를 알려 주세요.',
  'signup.pwAgain': '비밀번호만 다시 한번 입력해 주세요.',
  'signup.id': 'ID',
  'signup.idTitle': '소문자 영문, 숫자, 밑줄만. 30자까지.',
  'signup.idHelpPre': '소문자 영문, 숫자, _(밑줄). 30자까지. 예: ',
  'signup.password': '비밀번호',
  'signup.passwordHelp': '8자 이상.',
  'signup.inviteCode': '초대 코드',
  'signup.create': '만들기',
  'signup.haveAccountPre': '이미 살고 있는 분은 ',
  'signup.haveAccountLink': '이쪽에서 들어올 수 있어요',
  'signup.haveAccountPost': '.',
  'signup.backToFront': '첫 페이지로 돌아가기',

  // ── 들어가기(login)──────────────────────────────────
  'login.title': '들어가기',
  'login.tagline': '아이디와 비밀번호를 알려 주세요.',
  'login.id': '아이디 (@ 뒤의 이름)',
  'login.password': '비밀번호',
  'login.submit': '들어가기',
  'login.invalid': '아이디나 비밀번호를 찾지 못했어요.',
  'login.failed': '잘 들어가지 못했어요. 다시 한번.',
  'login.toSignup': '아직 처음인 분은 이쪽으로.',

  // ── 비밀번호 변경(password)──────────────────────────
  'password.title': '비밀번호 변경',
  'password.tagline': '@{username} 의 비밀번호를 새로 바꿔요.',
  'password.current': '지금 비밀번호',
  'password.new': '새 비밀번호 (8자 이상)',
  'password.confirm': '새 비밀번호 다시 한번',
  'password.submit': '바꾸기',
  'password.back': '돌아가기',
  'password.errCurrent': '지금 비밀번호가 다른 것 같아요.',
  'password.errMismatch': '새 비밀번호 두 개가 맞지 않아요.',
  'password.errShort': '비밀번호는 8자 이상으로 해 주세요.',
  'password.errAuth': '다시 한번 들어와 주세요.',
  'password.failed': '잘 바꾸지 못했어요. 다시 한번.',
  'password.doneTitle': '바뀌었어요',
  'password.doneNotice': '모든 기기에서 한번 로그아웃했어요. 새 비밀번호로 다시 들어와 주세요.',

  // ── 통로(check)───────────────────────────────────────
  'check.err.invite_code_required': '초대 코드를 입력해 주세요.',
  'check.err.invite_invalid': '그 초대 코드는 찾을 수 없었어요.',
  'check.err.invite_used': '그 초대 코드는 이미 사용되었어요.',
  'check.err.invite_expired': '그 초대 코드는 이미 만료되었어요.',
  'check.err.password_too_short': '비밀번호는 8자 이상으로.',
  'check.err.validation_failed': '입력한 것 중에 무언가 하나 다시 살펴봐 주세요.',
  'check.err.client_credentials_required': '서버와의 첫 악수가 이루어지지 않았어요.',
  'check.err.token_mint_failed': '계정은 만들어졌는데 들어갈 표가 나오지 않았어요.',
  'check.err.gateway_not_connected': '서버에 아직 닿지 않았어요. 조금 기다렸다가 다시 한번.',
  'check.err.gateway_rpc_failed': '서버에 아직 닿지 않았어요. 조금 기다렸다가 다시 한번.',
  'check.err.internal_error': '서버 안에서 무언가 넘어졌어요.',
  'check.err.no_draft': '초안을 찾을 수 없었어요. 다시 처음부터 부탁해요.',
  'check.err.password_missing': '비밀번호를 다시 한번 입력해 주세요.',
  'check.field.username': 'ID',
  'check.field.password': '비밀번호',
  'check.field.email': '메일',
  'check.field.invite_code': '초대 코드',
  'check.unknownIntent': '무엇을 할지 알 수 없게 되어 버렸어요.',
  'check.creatingAccount': '계정을 만들고 있어요…',
  'check.guidingLogin': '로그인 화면으로 안내하고 있어요…',
  'check.pleaseWaitTitle': '잠시만 기다려 주세요…',
  'check.pleaseWait': '잠깐만 기다려 주세요.',
  'check.failedTitle': '잘 진행되지 않았어요.',
  'check.failedGeneric': '잘 진행되지 않았어요. 다시 한번 해볼까요?',
  'check.retry': '다시 한번',
  'check.signupDraftKeptPre': '입력한 내용은 아직 남아 있어요. ',
  'check.signupDraftKeptLink': '폼으로 돌아가기',
  'check.signupDraftKeptPost': '도 할 수 있어요.',

  // ── 타임라인 ─────────────────────────────────────────
  'timeline.tabsLabel': '타임라인 고르기',
  'timeline.tabHome': '홈',
  'timeline.tabPublic': '모두',
  'timeline.tabTag': '태그',
  'timeline.tagLabel': '태그 (#은 필요 없어요)',
  'timeline.tagPlaceholder': '예: 고요',
  'timeline.emptyHome':
    '아직 홈에 아무것도 닿지 않았어요. 누군가를 팔로우하면 여기에 모여요.',
  'timeline.emptyTagPrompt': '위 입력란에 보고 싶은 태그를 넣어 주세요.',
  'timeline.emptyTag': '「#{tag}」가 붙은 글은 아직 찾을 수 없어요.',
  'timeline.emptyGeneric': '아직 아무것도 닿지 않았어요.',

  // ── 알림 ─────────────────────────────────────────────
  'notif.title': '알림',
  'notif.clearAll': '모두 지우기',
  'notif.confirmClear': '알림을 모두 지울까요?',
  'notif.empty': '아직 알림은 없어요.',
  'notif.dismiss': '이 알림 지우기',
  'notif.favourited': '님이 즐겨찾기에 담았어요',
  'notif.reblogged': '님이 부스트했어요',
  'notif.followed': '님이 팔로우했어요',
  'notif.followRequest': '님이 팔로우를 신청했어요',
  'notif.mentioned': '님이 답장을 보냈어요',
  'notif.posted': '님이 글을 올렸어요',
  'notif.pollEnded': '님의 투표가 마감되었어요',
  'notif.updated': '님이 글을 수정했어요',
  'notif.reacted': '님이 반응했어요',
  'notif.generic': '님의 알림',

  // ── 메시지 ───────────────────────────────────────────
  'messages.title': '메시지',
  'messages.empty':
    '아직 누구와도 주고받은 게 없어요. 지정한 상대에게만 닿는 글이 여기에 모여요.',
  'messages.self': '나',
  'messages.nameSep': ', ',
  'messages.unread': '안 읽음',
  'messages.openThread': '스레드 열기',

  // ── 찾기 ─────────────────────────────────────────────
  'search.title': '찾기',
  'search.labelPre': '이름, ID 또는 ',
  'search.placeholder': '예: alice / @alice@mastodon.social / #고요',
  'search.searchingRemote': '멀리까지 물어보고 있어요…',
  'search.searching': '찾고 있어요…',
  'search.submit': '찾기',
  'search.errorRemote': '멀리 있는 사람을 찾지 못했어요. 서버 철자를 확인해 봐 주세요.',
  'search.errorLocal': '잘 찾지 못했어요.',
  'search.notFound': '「{q}」는 찾을 수 없었어요.',
  'search.remoteHintPre': '멀리 있는 사람이라면 ',
  'search.remoteHintPost': ' 형태로 써 봐 주세요.',
  'search.sectionPeople': '사람',
  'search.sectionTags': '태그',

  // ── 리스트 목록 ──────────────────────────────────────
  'lists.title': '리스트',
  'lists.newPlaceholder': '새 리스트 이름',
  'lists.create': '만들기',
  'lists.empty': '아직 리스트가 없어요. 위에서 만들 수 있어요.',
  'lists.delete': '삭제',
  'lists.confirmDelete': '「{title}」를 삭제할까요?',
  'lists.exclusiveLabel': '홈에 표시하지 않기 (서클로 사용)',
  'lists.exclusiveShort': '홈에 표시 안 함',
  'lists.addTo': '리스트에 추가',

  // ── 리스트 안 ────────────────────────────────────────
  'listDetail.fallbackTitle': '리스트',
  'listDetail.listIndex': '리스트 목록',
  'listDetail.notFound': '이 리스트는 찾을 수 없었어요.',
  'listDetail.toListIndex': '리스트 목록으로',
  'listDetail.members': '멤버',
  'listDetail.addPlaceholder': '@user 또는 @user@host',
  'listDetail.add': '더하기',
  'listDetail.notFoundPerson': '그 사람은 찾을 수 없었어요.',
  'listDetail.addFailed': '더하지 못했어요.',
  'listDetail.noMembers': '아직 아무도 없어요.',
  'listDetail.empty':
    '이 리스트에는 아직 아무것도 흐르지 않았어요. 멤버를 더하면 여기에 모여요.',
  'listDetail.removeMember': '빼기',
  'listDetail.followHint': '팔로우하면 이 사람의 글이 여기에 흘러요.',

  // ── 즐겨찾기 ─────────────────────────────────────────
  'favourites.title': '즐겨찾기',
  'favourites.empty': '아직 즐겨찾기가 없어요.',

  // ── 북마크 ───────────────────────────────────────────
  'bookmarks.title': '북마크',
  'bookmarks.empty': '아직 책갈피를 끼우지 않았어요.',

  // ── OAuth 콜백 ───────────────────────────────────────
  'callback.serverError': '서버에서 「{err}」라고 답했어요.',
  'callback.urlMissing': 'url 에 빠진 게 있는 것 같아요.',
  'callback.failedTitle': '잘 들어가지 못했어요.',
  'callback.entering': '들어가고 있어요…',

  // ── 프로필 ───────────────────────────────────────────
  'profile.edit': '편집',
  'profile.unmute': '뮤트 풀기',
  'profile.mute': '뮤트하기',
  'profile.unblock': '차단 풀기',
  'profile.block': '차단하기',
  'profile.followingSuffix': '팔로잉',
  'profile.followersSuffix': '팔로워',
  'profile.postsSuffix': '게시물',
  'profile.pinned': '고정됨',
  'profile.empty': '아직 게시물이 없어요.',

  // ── 스레드 ───────────────────────────────────────────
  'thread.noteNotFound': '그 글은 찾을 수 없었어요.',
  'thread.reply': '답장하기'
};
