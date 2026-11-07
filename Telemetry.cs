using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace AccOverlay {
 public sealed class Frame {
  public int Packet, Status, Session, Laps, Current, Last, Best, Sector, Split;
  public float Remaining, Position;
  public int SessionIndex;
  public bool Valid=true;
 }
 public sealed class Reader : IDisposable {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr MapViewOfFile(IntPtr handle,uint access,uint hi,uint lo,UIntPtr size);
  [DllImport("kernel32.dll")] static extern bool UnmapViewOfFile(IntPtr p);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr p);
  IntPtr handle, view;
  public Frame Read() {
   if(view==IntPtr.Zero) {
    handle=OpenFileMapping(4,false,"Local\\acpmf_graphics");
    if(handle==IntPtr.Zero) return null;
    view=MapViewOfFile(handle,4,0,0,new UIntPtr(1412));
    if(view==IntPtr.Zero) { Dispose(); return null; }
   }
   byte[] b=new byte[1412];
   for(int retry=0;retry<3;retry++) {
    int packet=Marshal.ReadInt32(view);
    Marshal.Copy(view,b,0,b.Length);
    if(packet!=Marshal.ReadInt32(view)) continue;
    return Decode(b);
   }
   return null;
  }
  public static Frame Decode(byte[] b) {
   if(b==null || b.Length<1412) throw new ArgumentException("Incomplete ACC graphics page");
   int best=BitConverter.ToInt32(b,148);
   if(best<=0 || best==int.MaxValue) best=ParseTime(Encoding.Unicode.GetString(b,72,30).TrimEnd('\0'));
   return new Frame { Packet=BitConverter.ToInt32(b,0),Status=BitConverter.ToInt32(b,4),Session=BitConverter.ToInt32(b,8),Laps=BitConverter.ToInt32(b,132),Current=BitConverter.ToInt32(b,140),Last=BitConverter.ToInt32(b,144),Best=best,Remaining=BitConverter.ToSingle(b,152),Sector=BitConverter.ToInt32(b,164),Split=BitConverter.ToInt32(b,168),Position=BitConverter.ToSingle(b,248),SessionIndex=BitConverter.ToInt32(b,1320),Valid=BitConverter.ToInt32(b,1408)!=0 };
  }
  public static int ParseTime(string text) {
   TimeSpan value;
   return TimeSpan.TryParseExact(text,new string[]{@"m\:ss\.fff",@"mm\:ss\.fff",@"m\:ss\:fff",@"mm\:ss\:fff"},CultureInfo.InvariantCulture,out value) && value.TotalMilliseconds>0 && value.TotalMilliseconds<int.MaxValue?(int)value.TotalMilliseconds:0;
  }
  public void Dispose() { if(view!=IntPtr.Zero) UnmapViewOfFile(view); if(handle!=IntPtr.Zero) CloseHandle(handle); view=handle=IntPtr.Zero; }
 }
 public sealed class Timing {
  readonly List<LapRecord> history=new List<LapRecord>();
  public LapRecord[] History { get { return history.ToArray(); } }
  public int[] Sectors=new int[3], Previous=new int[3];
  public int?[] Differences=new int?[3];
  public int? LapDifference;
  public int Laps, Best, LastLap;
  public bool BestIsObserved;
  int officialBest, observedBest;
  Frame prior;
  int previousLap;
  int[] lapSectors=new int[3];
  bool[] sectorEstimated=new bool[3];
  bool[] previousEstimated=new bool[3], pendingEstimated;
  int pendingBoundaryClock, pendingBoundaryMin;
  int pendingLocalTotal;
  long lastSampleAt;
  int[] pendingSectors;
  int pendingLast;
  bool pendingFull, pendingValid;
  int pendingSector;
  int[] completedDisplay;
  int?[] completedDifferences;
  bool[] completedEstimatedDifferences=new bool[3];
  long holdUntil;
  long wrapWaitSince=-1;
  long lapCounterWaitSince=-1;
  bool lapValid=true;
  List<float> positions=new List<float>(); List<int> times=new List<int>();
  float[] referencePositions=new float[0]; int[] referenceTimes=new int[0];
  bool fullLap;
  public int? LiveDifference;
  int? positionEstimate;
  public bool HasReference { get { return referencePositions.Length>1; } }
  public int ReferenceSamples { get { return referencePositions.Length; } }
  public int RecordedLaps { get { return history.Count; } }
  public void Reset() { history.Clear(); sectorEstimated=new bool[3]; previousEstimated=new bool[3]; pendingEstimated=null; completedEstimatedDifferences=new bool[3]; pendingLocalTotal=pendingBoundaryClock=pendingBoundaryMin=0; lastSampleAt=0; Sectors=new int[3]; Previous=new int[3]; Differences=new int?[3]; lapSectors=new int[3]; pendingSectors=completedDisplay=null; completedDifferences=null; holdUntil=0; wrapWaitSince=lapCounterWaitSince=-1; pendingSector=0; LapDifference=LiveDifference=positionEstimate=null; Laps=Best=LastLap=previousLap=officialBest=observedBest=0; BestIsObserved=false; lapValid=true; prior=null; positions.Clear(); times.Clear(); referencePositions=new float[0]; referenceTimes=new int[0]; fullLap=false; }
  void Record(int index,int value) { if(value<=0) return; Sectors[index]=value; Differences[index]=Previous[index]>0?(int?)(value-Previous[index]):null; }
  static bool ValidTime(int value) { return value>0 && value<int.MaxValue; }
  void CaptureBoundary(int sector,int cumulative,bool estimated) {
   if(sector==1) { lapSectors[0]=cumulative; sectorEstimated[0]=estimated; Record(0,cumulative); }
   else if(sector==2 && lapSectors[0]>0 && cumulative>lapSectors[0]) { lapSectors[1]=cumulative-lapSectors[0]; sectorEstimated[1]=estimated || sectorEstimated[0]; Record(1,lapSectors[1]); }
  }
  static long ClockMs() { return (long)(Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency); }
  public void Update(Frame f) { Update(f,ClockMs()); }
  public void Update(Frame f,long now) {
   if(f.Status==0) { Reset(); return; }
   if(f.Status==1) { Reset(); return; }
   if(prior!=null && (f.Session!=prior.Session || f.SessionIndex!=prior.SessionIndex || f.Laps<prior.Laps)) Reset();
   // The counter can advance before the clock/position reset. Wait for the
   // matching new-lap clock without appending an old-lap sample to the new lap.
   if(prior!=null && f.Laps==prior.Laps+1 && prior.Current>1000 && f.Current>=prior.Current) {
    if(lapCounterWaitSince<0) lapCounterWaitSince=now;
    if(now-lapCounterWaitSince<1500) return;
   } else lapCounterWaitSince=-1;
   // Position/clock can wrap a packet before the completed-lap counter does.
   if(prior!=null && prior.Current>1000 && f.Laps==prior.Laps && ((prior.Position>0.90f && f.Position<0.02f) || (prior.Sector==2 && f.Sector==0 && f.Current+1000<prior.Current && f.Current<2000))) {
    if(wrapWaitSince<0) wrapWaitSince=now;
    if(now-wrapWaitSince<1000) return;
   } else wrapWaitSince=-1;
   Laps=f.Laps; if(f.Last>0 && f.Last<int.MaxValue) LastLap=f.Last;
   if(f.Best>0 && f.Best<int.MaxValue) officialBest=f.Best;
   if(prior!=null && f.Laps==prior.Laps && f.Current+1000<prior.Current) {
    // A return to the garage/restart is not a completed lap.
    lapSectors=new int[3]; Sectors=new int[3]; Differences=new int?[3];
    pendingSector=0; pendingSectors=completedDisplay=null; holdUntil=0;
    positions.Clear(); times.Clear();
    fullLap=false; lapValid=f.Valid; LiveDifference=null; prior=null;
   }
   if(prior!=null) {
    if(f.Laps==prior.Laps+1) {
     if(positions.Count>1) { referencePositions=positions.ToArray(); referenceTimes=times.ToArray(); }
     else { referencePositions=new float[0]; referenceTimes=new int[0]; }
     positions.Clear(); times.Clear(); positions.Add(0); times.Add(0);
     pendingFull=fullLap; pendingValid=lapValid; fullLap=true;
     pendingSectors=(int[])lapSectors.Clone(); pendingLast=prior.Last;
     pendingEstimated=(bool[])sectorEstimated.Clone();
     pendingLocalTotal=prior.Current>0 && f.Current>=0 && f.Current<1000?(int)Math.Max(0,prior.Current+Math.Min(250,Math.Max(0,now-lastSampleAt))-f.Current):0;
     holdUntil=now+5000;
     lapSectors=new int[3]; sectorEstimated=new bool[3]; pendingSector=0;
    } else if(f.Laps>prior.Laps+1) { Previous=new int[3]; Sectors=new int[3]; lapSectors=new int[3]; pendingSectors=completedDisplay=null; holdUntil=0; pendingSector=0; Differences=new int?[3]; positions.Clear(); times.Clear(); referencePositions=new float[0]; referenceTimes=new int[0]; fullLap=false; previousLap=f.Last; LapDifference=null; }
    else if(f.Sector!=prior.Sector && f.Sector>0 && f.Sector<=2 && f.Sector==prior.Sector+1) {
     if(f.Sector==1) { Sectors=new int[3]; Differences=new int?[3]; }
     pendingSector=f.Sector;
     pendingBoundaryClock=f.Current; pendingBoundaryMin=prior.Current;
     // Record the crossing ourselves; official split data can refine it below.
     // Sampling at 60 Hz has a small timing uncertainty, marked in the display.
     if(f.Current>0 && prior.Current>0 && f.Current>=prior.Current && f.Current-prior.Current<=1000) CaptureBoundary(f.Sector,f.Current,true);
    }
   } else {
    previousLap=history.Count>0?history[history.Count-1].Total:(ValidTime(f.Last)?f.Last:0);
    if(observedBest==0 || (previousLap>0 && previousLap<observedBest)) observedBest=previousLap;
    fullLap=f.Current<=1000 && f.Sector==0 && f.Position<0.01f;
    if(fullLap) { positions.Add(0); times.Add(0); }
    if(f.Sector==1 && f.Split>0 && f.Split<=f.Current) { lapSectors[0]=f.Split; Record(0,f.Split); }
   }
   // ACC publishes cumulative split times; wait if the split lags the sector index.
   if(pendingSector==f.Sector && pendingSector>0 && ValidTime(f.Split) && (f.Current==0 || f.Split<=f.Current) && (pendingBoundaryClock==0 || (f.Split>=pendingBoundaryMin-100 && f.Split<=pendingBoundaryClock+100))) {
    CaptureBoundary(pendingSector,f.Split,false);
    if((pendingSector==1 && lapSectors[0]>0 && !sectorEstimated[0]) || (pendingSector==2 && lapSectors[1]>0)) pendingSector=0;
   }
   // The lap counter can arrive before the final lap time.
   int finishedTotal=ValidTime(f.Last)?f.Last:((now>=holdUntil-4500)?pendingLocalTotal:0);
   if(pendingSectors!=null && ValidTime(finishedTotal) && (finishedTotal!=pendingLast || (f.Current>=300 && f.Current<=finishedTotal/2))) {
    Sectors=(int[])pendingSectors.Clone();
    LastLap=finishedTotal;
    if(Sectors[0]>0 && Sectors[1]>0) Record(2,finishedTotal-Sectors[0]-Sectors[1]);
    LapDifference=previousLap>0?(int?)(finishedTotal-previousLap):null;
    if(observedBest==0 || finishedTotal<observedBest) observedBest=finishedTotal;
    // Official ACC best remains authoritative. Only locally recorded valid, full
    // laps may fill in while the game has not published its best yet.
    if(pendingFull && pendingValid && ValidTime(f.Last) && (officialBest==0 || finishedTotal<officialBest)) officialBest=finishedTotal;
    if(referencePositions.Length>0 && referencePositions[referencePositions.Length-1]<1 && finishedTotal>referenceTimes[referenceTimes.Length-1]) {
     int length=referencePositions.Length; Array.Resize(ref referencePositions,length+1); Array.Resize(ref referenceTimes,length+1); referencePositions[length]=1; referenceTimes[length]=finishedTotal;
    }
    bool[] recordedEstimated=pendingEstimated ?? new bool[3];
    recordedEstimated[2]=recordedEstimated[0] || recordedEstimated[1] || !ValidTime(f.Last);
    history.Add(new LapRecord(f.Laps,finishedTotal,Sectors,recordedEstimated,!ValidTime(f.Last)));
    for(int i=0;i<3;i++) completedEstimatedDifferences[i]=recordedEstimated[i] || previousEstimated[i];
    completedDisplay=(int[])Sectors.Clone(); completedDifferences=(int?[])Differences.Clone();
    previousLap=finishedTotal; Previous=(int[])Sectors.Clone(); previousEstimated=(bool[])recordedEstimated.Clone(); pendingSectors=null;
    lapValid=f.Valid;
   }
   Best=officialBest>0?officialBest:observedBest; BestIsObserved=officialBest==0 && observedBest>0;
   LiveDifference=null; positionEstimate=null;
   bool waitingForPosition=f.Laps>0 && f.Current<1000 && f.Position>0.90f;
   if(!waitingForPosition && f.Position>=0 && f.Position<=1 && f.Current>=0) {
    int index=Array.BinarySearch(referencePositions,f.Position);
    if(index>=0) LiveDifference=f.Current-referenceTimes[index];
    else { index=~index;
    if(index>0 && index<referencePositions.Length) {
     float span=referencePositions[index]-referencePositions[index-1];
     int gap=referenceTimes[index]-referenceTimes[index-1];
     if(span>0 && gap>0 && gap<=30000) {
      int delta=f.Current-(int)(referenceTimes[index-1]+gap*(f.Position-referencePositions[index-1])/span);
      if(gap<=2000) LiveDifference=delta; else positionEstimate=delta;
     }
    }
    }
    if(positions.Count==0 || (f.Position>positions[positions.Count-1]+0.0001f && f.Current>times[times.Count-1])) { positions.Add(f.Position); times.Add(f.Current); }
    else if(positions.Count>0 && f.Position<positions[positions.Count-1]-0.02f) { fullLap=false; positions.Clear(); times.Clear(); }
   }
   lapValid=lapValid && f.Valid;
   lastSampleAt=now;
   prior=f;
  }
  public Display GetDisplay() { return GetDisplay(ClockMs()); }
  public Display GetDisplay(long now) {
   Display d=new Display();
   if(prior==null) return d;
   d.Holding=completedDisplay!=null && now<holdUntil;
   if(d.Holding) { d.Sectors=(int[])completedDisplay.Clone(); d.Differences=(int?[])completedDifferences.Clone(); d.EstimatedDifferences=(bool[])completedEstimatedDifferences.Clone(); d.Lap=LastLap; d.LapDelta=LapDifference; d.LapDeltaEstimated=(history.Count>0 && history[history.Count-1].EstimatedTotal) || (history.Count>1 && history[history.Count-2].EstimatedTotal); return d; }
   d.Sectors=(int[])lapSectors.Clone();
   for(int i=0;i<3;i++) if(d.Sectors[i]>0 && Previous[i]>0) d.Differences[i]=d.Sectors[i]-Previous[i];
   int sector=prior.Sector;
   if(sector>=0 && sector<3) {
    int elapsed=0; bool known=true;
    for(int i=0;i<sector;i++) { if(lapSectors[i]<=0) known=false; elapsed+=lapSectors[i]; }
    // S3 can be timed from its cumulative boundary even on a partial recording.
    if(!known && sector==2 && prior.Split>0 && prior.Split<=prior.Current) { elapsed=prior.Split; known=true; }
    if(known) { d.Sectors[sector]=Math.Max(0,prior.Current-elapsed); d.ActiveSector=sector; }
   }
   // Compare completed sectors with our own previous-lap record, even if the
   // position-based reference is missing at the current point on the track.
   int cumulative=0, referenceCumulative=0; bool haveCompleted=false;
   for(int i=0;i<prior.Sector && i<3;i++) {
    if(lapSectors[i]<=0 || Previous[i]<=0) { haveCompleted=false; break; }
    cumulative+=lapSectors[i]; referenceCumulative+=Previous[i]; haveCompleted=true;
   }
   d.Lap=prior.Current; d.LapDelta=LiveDifference ?? (haveCompleted?(int?)(cumulative-referenceCumulative):positionEstimate);
   d.DeltaStatus=LiveDifference.HasValue?"Текущая дельта":(haveCompleted?"По завершённым секторам":(positionEstimate.HasValue?"Оценка по записи":(referencePositions.Length>1?"Нет записи этой точки":(history.Count>0?"Нет точек прошлого круга":"Нет записанного круга"))));
   if(!LiveDifference.HasValue && !haveCompleted && positionEstimate.HasValue) d.LapDeltaEstimated=true;
   if(!LiveDifference.HasValue && haveCompleted) for(int i=0;i<prior.Sector && i<3;i++) d.LapDeltaEstimated|=sectorEstimated[i] || previousEstimated[i];
   if(previousLap>0) {
    int forecast=previousLap+(d.LapDelta ?? 0);
    if(forecast>prior.Current) d.Forecast=forecast;
   }
   for(int i=0;i<3;i++) d.EstimatedDifferences[i]=sectorEstimated[i] || previousEstimated[i];
   return d;
  }
  public static string Time(int ms) { return ms<=0?"--:--.---":string.Format("{0}:{1:00}.{2:000}",ms/60000,(ms/1000)%60,ms%1000); }
  public static string Delta(int? ms) { return ms.HasValue?string.Format(System.Globalization.CultureInfo.InvariantCulture,"{0:+0.000;-0.000;0.000}",ms.Value/1000.0):"—"; }
 }
 public sealed class Display {
  public int[] Sectors=new int[3];
  public int?[] Differences=new int?[3];
  public int Lap, ActiveSector=-1;
  public int? LapDelta;
  public bool LapDeltaEstimated;
  public bool Holding;
  public int Forecast;
  public bool[] EstimatedDifferences=new bool[3];
  public string DeltaStatus="Нет записанного круга";
 }
 public sealed class LapRecord {
  public readonly int Number, Total;
  public readonly bool EstimatedTotal;
  public readonly int[] Sectors;
  public readonly bool[] EstimatedSectors;
  public LapRecord(int number,int total,int[] sectors,bool[] estimated,bool estimatedTotal) { Number=number; Total=total; Sectors=(int[])sectors.Clone(); EstimatedSectors=(bool[])estimated.Clone(); EstimatedTotal=estimatedTotal; }
 }
}
