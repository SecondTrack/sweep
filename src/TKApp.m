#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/wait.h>
#import <mach/mach.h>
#import <spawn.h>
#import "MeshL10n.h"

extern char **environ;
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);   // libproc (libSystem)

// iOS-nativer heller Look (wie die anderen Tools), Akzent = frisches Cyan.
#define BG    [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1]
#define CARD  [UIColor whiteColor]
#define INK   [UIColor blackColor]
#define MUT   [UIColor colorWithWhite:0.56 alpha:1]
#define LINE  [UIColor colorWithRed:0.82 green:0.82 blue:0.84 alpha:1]
#define CYAN  [UIColor colorWithRed:0.20 green:0.68 blue:0.90 alpha:1]
#define RED   [UIColor colorWithRed:1.00 green:0.23 blue:0.19 alpha:1]

static long long gTotalRAM(void){ return (long long)[NSProcessInfo processInfo].physicalMemory; }
static long long gFreeRAM(void){
    mach_port_t host=mach_host_self();
    vm_size_t ps=0; host_page_size(host,&ps);
    vm_statistics_data_t vm; mach_msg_type_number_t cnt=HOST_VM_INFO_COUNT;
    if(host_statistics(host,HOST_VM_INFO,(host_info_t)&vm,&cnt)!=KERN_SUCCESS) return 0;
    return (long long)(vm.free_count + vm.inactive_count) * (long long)ps;
}
static NSString* mb(long long b){ return [NSString stringWithFormat:@"%lld MB",(b+524288)/1048576]; }

// Laufende .app-Prozesse -> @[ {name, pid} ] (ohne SpringBoard + uns selbst).
static NSArray* gRunningApps(void){
    int mib[4]={CTL_KERN,KERN_PROC,KERN_PROC_ALL,0};
    size_t len=0; if(sysctl(mib,4,NULL,&len,NULL,0)<0||!len) return @[];
    struct kinfo_proc *procs=malloc(len);
    if(!procs) return @[];
    if(sysctl(mib,4,procs,&len,NULL,0)<0){ free(procs); return @[]; }
    int n=(int)(len/sizeof(struct kinfo_proc));
    NSMutableArray *out=[NSMutableArray array];
    pid_t me=getpid();
    for(int i=0;i<n;i++){
        pid_t pid=procs[i].kp_proc.p_pid;
        if(pid<=1 || pid==me) continue;
        char path[1024]; path[0]=0;
        if(proc_pidpath(pid,path,(uint32_t)sizeof path)<=0) continue;
        char *dot=strstr(path,".app/");
        if(!dot) continue;                 // kein App-Prozess
        *dot=0;                            // bei ".app" abschneiden
        char *slash=strrchr(path,'/');
        if(!slash) continue;
        NSString *name=[NSString stringWithUTF8String:slash+1];
        if(!name.length || [name isEqualToString:@"SpringBoard"]) continue;   // SpringBoard NICHT killen
        [out addObject:@{@"name":name,@"pid":@(pid)}];
    }
    free(procs);
    [out sortUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){ return [a[@"name"] caseInsensitiveCompare:b[@"name"]]; }];
    return out;
}

// ============================ View-Controller ============================
@interface TKViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@implementation TKViewController {
    UITableView *_table;
    NSArray *_apps;
    UILabel *_ramBig, *_ramSub, *_freed;
    UIView *_barFill, *_barTrack;
    CGFloat _W;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=BG;
    _W=self.view.bounds.size.width;

    UILabel *t=[[UILabel alloc] initWithFrame:CGRectMake(16,24,_W-32,30)];
    t.text=L(@"Tasks"); t.font=[UIFont boldSystemFontOfSize:24]; t.textColor=INK; t.backgroundColor=[UIColor clearColor]; [self.view addSubview:t];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,58,_W,self.view.bounds.size.height-58) style:UITableViewStylePlain];
    _table.dataSource=self; _table.delegate=self; _table.backgroundColor=BG;
    _table.separatorColor=LINE; _table.rowHeight=56;
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _table.tableHeaderView=[self buildHeader];
    [self.view addSubview:_table];
}

- (UIView *)buildHeader {
    UIView *h=[[UIView alloc] initWithFrame:CGRectMake(0,0,_W,186)];
    // RAM-Karte
    UIView *card=[[UIView alloc] initWithFrame:CGRectMake(12,8,_W-24,112)];
    card.backgroundColor=CARD; card.layer.cornerRadius=10; card.layer.borderWidth=0.5; card.layer.borderColor=LINE.CGColor; [h addSubview:card];
    UILabel *cap=[[UILabel alloc] initWithFrame:CGRectMake(16,12,_W-24-32,16)]; cap.text=L(@"Free memory"); cap.font=[UIFont systemFontOfSize:12]; cap.textColor=MUT; cap.backgroundColor=[UIColor clearColor]; [card addSubview:cap];
    _ramBig=[[UILabel alloc] initWithFrame:CGRectMake(16,28,_W-24-32,34)]; _ramBig.font=[UIFont boldSystemFontOfSize:30]; _ramBig.textColor=INK; _ramBig.backgroundColor=[UIColor clearColor]; [card addSubview:_ramBig];
    _freed=[[UILabel alloc] initWithFrame:CGRectMake(_W-24-150,28,134,34)]; _freed.font=[UIFont boldSystemFontOfSize:14]; _freed.textColor=CYAN; _freed.textAlignment=NSTextAlignmentRight; _freed.backgroundColor=[UIColor clearColor]; [card addSubview:_freed];
    _barTrack=[[UIView alloc] initWithFrame:CGRectMake(16,74,card.bounds.size.width-32,8)]; _barTrack.backgroundColor=[UIColor colorWithWhite:0.90 alpha:1]; _barTrack.layer.cornerRadius=4; _barTrack.clipsToBounds=YES; [card addSubview:_barTrack];
    _barFill=[[UIView alloc] initWithFrame:CGRectMake(0,0,0,8)]; _barFill.backgroundColor=CYAN; _barFill.layer.cornerRadius=4; [_barTrack addSubview:_barFill];
    _ramSub=[[UILabel alloc] initWithFrame:CGRectMake(16,86,_W-24-32,18)]; _ramSub.font=[UIFont systemFontOfSize:12]; _ramSub.textColor=MUT; _ramSub.backgroundColor=[UIColor clearColor]; [card addSubview:_ramSub];

    // "Alle schließen"
    UIButton *all=[UIButton buttonWithType:UIButtonTypeCustom];
    all.frame=CGRectMake(12,130,_W-24,46); all.backgroundColor=CYAN; all.layer.cornerRadius=10;
    [all setTitle:L(@"Close all") forState:UIControlStateNormal]; [all setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    all.titleLabel.font=[UIFont boldSystemFontOfSize:17];
    [all addTarget:self action:@selector(closeAll) forControlEvents:UIControlEventTouchUpInside]; [h addSubview:all];
    return h;
}

- (void)viewDidLoad { [super viewDidLoad]; [self refreshRAM]; [self refreshList]; }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; [self refreshRAM]; [self refreshList]; }

- (void)refreshRAM {
    long long tot=gTotalRAM(), fr=gFreeRAM();
    _ramBig.text=mb(fr);
    _ramSub.text=[NSString stringWithFormat:L(@"of %@ total"), mb(tot)];
    CGFloat frac=tot>0?(CGFloat)fr/(CGFloat)tot:0; if(frac>1)frac=1;
    CGRect f=_barFill.frame; f.size.width=_barTrack.bounds.size.width*frac; _barFill.frame=f;
}
- (void)refreshList { _apps=gRunningApps(); [_table reloadData]; }

- (void)killPids:(NSArray *)pids {
    if(!pids.count) return;
    long long before=gFreeRAM();
    const char *hp="/Applications/Tasks.app/tkkill";
    int argc=(int)pids.count+1;
    char **argv=calloc(argc+1,sizeof(char*));
    argv[0]=(char*)"tkkill";
    for(int i=0;i<(int)pids.count;i++) argv[i+1]=strdup([[pids[i] stringValue] UTF8String]);
    argv[argc]=NULL;
    pid_t p; int rc=posix_spawn(&p,hp,NULL,NULL,argv,environ);
    if(rc==0){ int st; waitpid(p,&st,0); }
    for(int i=0;i<(int)pids.count;i++) free(argv[i+1]);
    free(argv);
    // kurz warten, bis die Prozesse wirklich weg sind, dann RAM/Liste aktualisieren
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshRAM]; [self refreshList];
        long long freed=gFreeRAM()-before;
        if(freed>1048576){ _freed.text=[NSString stringWithFormat:@"+%@",mb(freed)]; }
    });
}
- (void)closeAll {
    NSMutableArray *pids=[NSMutableArray array];
    for(NSDictionary*a in _apps) [pids addObject:a[@"pid"]];
    [self killPids:pids];
}
- (void)killOne:(UIButton *)b {
    UIView *v=b; while(v && ![v isKindOfClass:[UITableViewCell class]]) v=v.superview;
    NSIndexPath *ip=[_table indexPathForCell:(UITableViewCell *)v];
    if(!ip || ip.row>=(NSInteger)_apps.count) return;
    [self killPids:@[_apps[ip.row][@"pid"]]];
}

// -------- Tabelle --------
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _apps.count; }
- (CGFloat)tableView:(UITableView *)t heightForHeaderInSection:(NSInteger)s { return 30; }
- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)s {
    UIView *v=[[UIView alloc] initWithFrame:CGRectMake(0,0,_W,30)]; v.backgroundColor=BG;
    UILabel *l=[[UILabel alloc] initWithFrame:CGRectMake(16,8,_W-32,18)];
    l.text=_apps.count?[NSString stringWithFormat:L(@"Running apps (%d)"),(int)_apps.count]:L(@"No apps running");
    l.font=[UIFont boldSystemFontOfSize:13]; l.textColor=MUT; l.backgroundColor=[UIColor clearColor]; [v addSubview:l];
    return v;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"r"];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"r"];
        c.selectionStyle=UITableViewCellSelectionStyleNone; c.backgroundColor=CARD;
        UILabel *nm=[[UILabel alloc] initWithFrame:CGRectMake(16,8,tv.bounds.size.width-16-90,24)]; nm.tag=1; nm.font=[UIFont boldSystemFontOfSize:16]; nm.textColor=INK; nm.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:nm];
        UILabel *pd=[[UILabel alloc] initWithFrame:CGRectMake(16,32,tv.bounds.size.width-16-90,16)]; pd.tag=2; pd.font=[UIFont systemFontOfSize:11]; pd.textColor=MUT; pd.backgroundColor=[UIColor clearColor]; [c.contentView addSubview:pd];
        UIButton *x=[UIButton buttonWithType:UIButtonTypeCustom]; x.tag=3; x.frame=CGRectMake(tv.bounds.size.width-78,11,62,34);
        x.backgroundColor=[UIColor colorWithRed:1 green:0.90 blue:0.90 alpha:1]; x.layer.cornerRadius=8;
        [x setTitle:L(@"Close") forState:UIControlStateNormal]; [x setTitleColor:RED forState:UIControlStateNormal]; x.titleLabel.font=[UIFont boldSystemFontOfSize:13];
        x.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
        [x addTarget:self action:@selector(killOne:) forControlEvents:UIControlEventTouchUpInside]; [c.contentView addSubview:x];
    }
    NSDictionary *a=_apps[ip.row];
    ((UILabel*)[c.contentView viewWithTag:1]).text=a[@"name"];
    ((UILabel*)[c.contentView viewWithTag:2]).text=[NSString stringWithFormat:@"PID %@",a[@"pid"]];
    return c;
}
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end

// ============================ App-Delegate ============================
@interface TKAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong,nonatomic) UIWindow *window;
@end
@implementation TKAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)o {
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController=[[TKViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
