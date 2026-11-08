using System;

namespace AccOverlay {
 // Synthetic telemetry goes through the production Timing model. The UI uses
 // its ordinary render loop and five-second hold; no test-only graph is drawn.
 public sealed class TestDrive {
  public readonly Timing Timing = new Timing();
  public long Now { get; private set; }
  public string Scenario { get; private set; }
  public bool AutoRun = true;
  public bool Driving { get; private set; }
  public int Seed { get; private set; }
  public int SimulatedLapTime { get { return duration; } }
  public bool SimulatedLapValid { get { return lapValid; } }
  readonly Random random;
  double waveA,waveB;
  bool lapValid;
  long lastWall, driveStart, nextDrive;
  int lap, last, best, duration, sessionIndex;
  bool haveWall;
  public TestDrive() : this(Environment.TickCount) { }
  public TestDrive(int seed) { Seed=seed;random=new Random(seed);Restart("Normal"); }
  void RandomLap() {
   duration=random.Next(86000,98001);
   waveA=random.Next(-1800,1801);waveB=random.Next(-650,651);
   lapValid=random.Next(8)!=0;
  }
  double Wave(int number,double progress) {
   return Scenario=="Random"?waveA*Math.Sin(progress*Math.PI*2)+waveB*Math.Sin(progress*Math.PI*4):(number>0?Math.Sin(progress*Math.PI*2)*900:0);
  }
  Frame Sample(int number,double progress,int total,int previous,bool valid,bool gaps) {
   double wave=Wave(number,progress);
   int current=(int)Math.Round(progress*total+wave);
   int sector=progress<1.0/3?0:(progress<2.0/3?1:2);
   double boundary=sector/3.0;
   int split=sector==0?0:(int)Math.Round(boundary*total+Wave(number,boundary));
   return new Frame { Status=2,Session=0,SessionIndex=sessionIndex,Laps=number,Current=current,Last=previous,Best=best,Position=(float)progress,Sector=sector,Split=split,Valid=valid };
  }
  void Feed(int number,int total,int previous,long start,bool partial,bool gaps,bool valid) {
   for(int i=partial?12:0;i<100;i++) {
    if(gaps && i>=40 && i<=55) continue;
    Frame f=Sample(number,i/100.0,total,previous,valid,gaps);
    Timing.Update(f,start+f.Current);
   }
   Timing.Update(new Frame { Status=2,SessionIndex=sessionIndex,Laps=number+1,Last=total,Best=best,Valid=true },start+total);
  }
  public void Restart(string scenario) {
   if(Array.IndexOf(new string[] { "Normal","Record","Invalid","MissingPackets","PartialReference","NoData","Random" },scenario)<0) throw new ArgumentException("Unknown test scenario");
   Scenario=scenario; Timing.Reset(); Driving=false; sessionIndex++;
   int first=scenario=="Record" || scenario=="Invalid"?90000:93000;
   duration=scenario=="Record" || scenario=="Invalid"?85000:90000;
   lapValid=scenario!="Invalid";
   if(scenario=="Random") { RandomLap();first=duration; }
   long finish=Now+200000;
   best=0;
   if(scenario=="NoData") {
    // A known previous result without a recorded trace.
    Timing.Update(new Frame { Status=2,SessionIndex=sessionIndex,Laps=0,Current=92000,Position=0.99f,Sector=2,Valid=true },finish-duration-1000);
    Timing.Update(new Frame { Status=2,SessionIndex=sessionIndex,Laps=1,Last=first,Best=first,Valid=true },finish-duration);
   } else Feed(0,first,0,finish-duration-first,scenario=="PartialReference",scenario=="MissingPackets",true);
   best=first;
   if(scenario=="Random") {
    // Keep the first trace's time origin fixed while choosing a new profile.
    int originalDuration=duration;RandomLap();finish+=duration-originalDuration;
   }
   Feed(1,duration,first,finish-duration,false,false,lapValid);
   Now=finish; lap=2; last=duration;
   if(lapValid) best=Math.Min(first,duration);
   nextDrive=Now+5000;
  }
  public void StartLap() {
   if(Driving) return;
   if(Scenario=="Random") RandomLap();
   // Explicit action may end a previous result early, just like a session reset.
   driveStart=Now; Driving=true;
  }
  public void ResetSession() { Timing.Reset(); Driving=false; AutoRun=false;lap=0;last=best=0;sessionIndex++; }
  public Display Tick(long wallMilliseconds) {
   long elapsed=haveWall?Math.Max(0,wallMilliseconds-lastWall):0;
   haveWall=true; lastWall=wallMilliseconds; Now+=elapsed;
   if(!Driving && AutoRun && Now>=nextDrive) StartLap();
   if(Driving) {
    double progress=Math.Min(1,(Now-driveStart)/3000.0);
    if(progress>=1) {
     Timing.Update(Sample(lap,0.9999,duration,last,lapValid,false),Now-1);
     Timing.Update(new Frame { Status=2,SessionIndex=sessionIndex,Laps=lap+1,Last=duration,Best=best,Valid=true },Now);
     // Repeated lap times are confirmed by the first new-lap sample as ACC
     // does; a finish alone can still be a stale Last packet to Timing.
     if(duration==last) Timing.Update(new Frame { Status=2,SessionIndex=sessionIndex,Laps=lap+1,Current=500,Position=0.005f,Last=duration,Best=best,Valid=true },Now);
     lap++;last=duration;if(lapValid) best=best>0?Math.Min(best,duration):duration;
     Driving=false;nextDrive=Now+5000;
    } else if(!(Scenario=="MissingPackets" && progress>=0.40 && progress<=0.55)) {
     Timing.Update(Sample(lap,progress,duration,last,lapValid,false),Now);
    }
   }
   return Timing.GetDisplay(Now);
  }
 }
}
