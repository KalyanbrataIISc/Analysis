"""Inspect EMG32 CCA, retaining float32 firmware operations and offline dimensions.

Sources: EMG32/src/{Filters,Analysis,CcaNeurofeedback}.cpp and include/Config.h.
The float32 replay is a numerical model, not a claim of bit-exact ESP32 execution.
"""
from pathlib import Path
import re
import numpy as np
import pandas as pd
from scipy import signal, linalg

ROOT = Path(__file__).resolve().parent.parent
CONFIG = (ROOT/"EMG32/include/Config.h").read_text(encoding="utf-8")
def define(name):
    match = re.search(r"^#define\s+"+name+r"\s+([^\s/]+)", CONFIG, re.M)
    if not match: raise ValueError(f"Missing configuration {name}")
    return match[1]
# Explicit support contract: fail loudly if the checked-out build changes.
for key, expected in {"ACTIVE_MONTAGE":"MONTAGE_16CH","ADS_SAMPLE_RATE":"SPS_250",
                      "CAR_ENABLED":"0","CCA_N_HARMONICS":"1","CCA_N_POWER_ITERS":"8",
                      "CCA_SMOOTHING":"5","TRIGGER_GATED_TX":"0"}.items():
    if define(key) != expected: raise ValueError(f"Update replay for {key}={define(key)}")
FS, WINDOW, HOP = 250, 250, 25
UV_PER_COUNT = float(define("UV_PER_COUNT").rstrip("f"))
GAIN = float(define("CCA_DIFF_GAIN").rstrip("f"))
EPS_REL = float(define("CCA_EPSILON_XX").rstrip("f"))
EPS_Y = float(define("CCA_EPSILON_YY").rstrip("f"))
TARGETS = (float(define("CCA_FREQ_A_HZ").rstrip("f")), float(define("CCA_FREQ_B_HZ").rstrip("f")))
CHANNEL_NAMES = [f"C{c}" for c in range(9,25)]
SIGNAL_COLUMNS = [f"ch{c}_uv" for c in range(9,25)]
RAW_COLUMNS = [f"raw{c}" for c in range(9,25)]
FILES = {"Paddle": ("eeg_20261006_153213","eeg_20261006_155629"),
         "Leaf": ("eeg_20261006_160348","eeg_20261006_161145")}
LABELS = {"Paddle": {20:"Left target",21:"Right target"},
          "Leaf": {20:"C1 / Pointing",21:"C2 / Moving"}}
table_text = (ROOT/"EMG32/include/CcaRefTables.h").read_text(encoding="utf-8")
def parse_array(name, shape):
    match = re.search(r"\b"+name+r"\s*\[[^;=]+?=\s*\{(.*?)\};",table_text,re.S)
    if not match: raise ValueError(f"Missing reference table {name}")
    content = re.sub(r"//[^\n]*","",match[1])
    values = re.findall(r"([+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)f",content)
    return np.array(values,dtype=np.float32).reshape(shape)
REFERENCES = {f:(parse_array("CCA_TABLE_Y_"+letter,(WINDOW,2)),
                 parse_array("CCA_TABLE_CYY_INV_"+letter,(2,2)))
              for f,letter in zip(TARGETS,("A","B"))}
filter_text = (ROOT/"EMG32/src/Filters.cpp").read_text(encoding="utf-8")
fir_body = re.search(r"FIR_TAPS\[FIR_LEN\]\s*=\s*\{(.*?)\};",filter_text,re.S)[1]
FIR_TAPS = np.array(re.findall(r"([+-]?\d+\.\d+)f",fir_body),float)
DC_R = float(define("DC_BLOCK_R").rstrip("f"))

def references(frequency, n=WINDOW):
    """Compiled tables at configured targets; generated sine/cosine for a scan."""
    if n == WINDOW and frequency in REFERENCES: return REFERENCES[frequency]
    t=np.arange(n)/FS
    y=np.column_stack((np.sin(2*np.pi*frequency*t),np.cos(2*np.pi*frequency*t)))
    y-=y.mean(0)
    return y.astype(np.float32), np.linalg.inv(y.T@y+EPS_Y*np.eye(2)).astype(np.float32)

def invert_float32(matrix):
    """Gauss-Jordan, same partial pivots, threshold and update order as firmware."""
    a=np.array(matrix,dtype=np.float32,copy=True); n=len(a); inv=np.eye(n,dtype=np.float32)
    for p in range(n):
        row=p+int(np.argmax(abs(a[p:,p])))
        if abs(a[row,p]) < np.float32(1e-12): return None
        if row != p:
            a[[p,row]]=a[[row,p]]; inv[[p,row]]=inv[[row,p]]
        invpivot=np.float32(1)/a[p,p]
        a[p]*=invpivot; inv[p]*=invpivot
        for r in range(n):
            if r != p:
                factor=a[r,p]
                if abs(factor)>np.float32(1e-12):
                    a[r]-=factor*a[p]; inv[r]-=factor*inv[p]
    return inv

def ordered_matvec(m,v):
    out=np.zeros(len(v),np.float32)
    for j in range(len(v)): out+=m[:,j]*v[j]
    return out

def ordered_sum(values):
    out=np.float32(0)
    for value in values: out=np.float32(out+value)
    return out

def power_trace(m, steps=8):
    """Always restarts with equal weights; saves initial vector and all updates."""
    m=np.asarray(m,np.float32); n=len(m)
    v=np.full(n,np.float32(1)/np.sqrt(np.float32(n)),np.float32)
    vectors=[v.copy()]; scores=[]; residuals=[]
    alive=True
    for _ in range(steps):
        if alive:
            new=ordered_matvec(m,v); norm=np.sqrt(ordered_sum(new*new))
            if norm < np.float32(1e-12): v=np.zeros(n,np.float32); alive=False
            else: v=new*(np.float32(1)/norm)
        eig=ordered_sum(v*ordered_matvec(m,v)) if alive else np.float32(0)
        vectors.append(v.copy()); scores.append(float(np.sqrt(max(eig,np.float32(0)))))
        residuals.append(float(np.linalg.norm(ordered_matvec(m,v)-eig*v)))
    return np.array(vectors),np.array(scores),np.array(residuals)

def prepare_window(eeg_uv):
    eeg=np.asarray(eeg_uv,np.float32)
    if eeg.shape != (WINDOW,16) or not np.isfinite(eeg).all():
        raise ValueError("Expected finite 250 x 16 board-filtered microvolts")
    sums=np.zeros(16,np.float32)
    for row in eeg: sums+=row
    means=sums/np.float32(WINDOW); x=eeg-means
    cxx=np.zeros((16,16),np.float32)
    for row in x: cxx+=row[:,None]*row[None,:]
    eps=max(np.float32(ordered_sum(np.diag(cxx))/np.float32(16)*np.float32(EPS_REL)),
            np.float32(1e-6))
    a=cxx.copy(); a.flat[::17]+=eps
    inv=invert_float32(a)
    if inv is None: raise ArithmeticError("Firmware inverse fails; board returns zeros and skips smoothing.")
    return dict(eeg=eeg,X=x,x_mean=means,Cxx=cxx,A=a,A_inv=inv,epsilon=float(eps))

def fit_window(eeg_uv, frequency, prepared=None):
    """Firmware float32 direction plus stable full-dimension mathematical diagnostic."""
    q=prepare_window(eeg_uv) if prepared is None else prepared
    y,binv=references(frequency)
    cxy=np.zeros((16,2),np.float32)
    for xrow,yrow in zip(q["X"],y): cxy+=xrow[:,None]*yrow[None,:]
    t1=cxy[:,0,None]*binv[0]+cxy[:,1,None]*binv[1]
    t2=t1[:,0,None]*cxy[None,:,0]+t1[:,1,None]*cxy[None,:,1]
    m=np.zeros((16,16),np.float32)
    for k in range(16): m+=q["A_inv"][:,k,None]*t2[k,None,:]
    vectors,scores,residuals=power_trace(m)
    v=vectors[-1]; u=q["X"]@v
    b=binv.astype(float)@cxy.astype(float).T@v.astype(float)
    if np.linalg.norm(b)>0: b/=np.linalg.norm(b)
    vv=y.astype(float)@b
    # Stable diagnostic: double precision sums, same relative-regularization rule.
    xd=np.array(eeg_uv,dtype=float,copy=True); xd-=xd.mean(0)
    yd=y.astype(float); cd=xd.T@xd; epsd=max(np.trace(cd)/16*EPS_REL,1e-6)
    ad=cd+epsd*np.eye(16); bd=np.linalg.inv(binv.astype(float)); bd=(bd+bd.T)/2
    cross=xd.T@yd
    lx=linalg.cholesky(ad,lower=True); ly=linalg.cholesky(bd,lower=True)
    h=linalg.solve_triangular(lx,cross,lower=True)
    h=linalg.solve_triangular(ly,h.T,lower=True).T
    left,strengths,right=linalg.svd(h,full_matrices=False)
    w=linalg.solve_triangular(lx.T,left,lower=False)
    rw=linalg.solve_triangular(ly.T,right.T,lower=False)
    unit=w/np.linalg.norm(w,axis=0,keepdims=True)
    for j in range(2):
        if unit[np.argmax(abs(unit[:,j])),j]<0:
            unit[:,j]*=-1; w[:,j]*=-1; rw[:,j]*=-1
    return dict(**q, Y=y,B_inv=binv,Cxy=cxy,T1=t1,T2=t2,M=m,
                frequency=frequency,hw_weights=v,hw_U=u,hw_V=vv,
                hardware_score=scores[-1],vectors=vectors,iteration_scores=scores,
                residuals=residuals,strengths=strengths,
                strengths_all=np.r_[strengths,np.zeros(14)],
                unit_weights=unit,weights=w,reference_weights=rw,
                U=xd@w,V=yd@rw,exact_U=xd@unit)

def nf_series(scores, gain=GAIN, startup_known=False, sequences=None):
    """Continuous state; do not reset at trial markers.

    With unknown board startup, first four outputs cannot be reconstructed.
    Later values require five consecutive logged hops. Inverse failures cannot
    be distinguished from valid zeros in CSV; parity flags expose differences.
    """
    values=np.clip(gain*(np.asarray(scores)[:,0]-np.asarray(scores)[:,1]),-1,1)
    out=np.full(len(values),np.nan)
    for i in range(len(values)):
        if startup_known and i<5: out[i]=values[i]
        elif i>=4:
            if sequences is None or np.all(np.diff(sequences[i-4:i+1])==HOP):
                out[i]=np.median(values[i-4:i+1])
    return out

def load_recordings(root=ROOT):
    records=[]; audits=[]
    for game,names in FILES.items():
        for name in names:
            folder=Path(root)/"data/2026-10-06"/name
            s=pd.read_csv(folder/(name+"_signals.csv"))
            f=pd.read_csv(folder/(name+"_features.csv"))
            # TYPE_CCA decoded legacy layout, explicit is_cca=1. Other rows are
            # duplicate/unrelated features, not independent CCA updates.
            f=f.loc[f.is_cca==1].drop_duplicates("seq").sort_values("seq").reset_index(drop=True)
            if not s.seq.is_monotonic_increasing or s.seq.duplicated().any():
                raise ValueError(f"Nonunique/out-of-order signal sequences in {name}")
            scores=f[["v3","v4"]].to_numpy()
            f["recorded_nf"]=f.v1
            f["nf_gain1"]=nf_series(scores,1,sequences=f.seq.to_numpy())
            f["nf_current_gain"]=nf_series(scores,GAIN,sequences=f.seq.to_numpy())
            seq=s.seq.to_numpy(); markers=s.marker.to_numpy()
            starts=np.flatnonzero(np.isin(markers,[20,21]) & np.r_[True,markers[1:]!=markers[:-1]])
            stops=np.flatnonzero((markers==30) & np.r_[True,markers[1:]!=markers[:-1]])
            trials=[]
            for j,start in enumerate(starts):
                next_start=starts[j+1] if j+1<len(starts) else len(s)
                end_candidates=stops[(stops>start)&(stops<next_start)]
                if not len(end_candidates): continue
                end=int(end_candidates[0]); code=int(markers[start]); endseq=min(seq[end],seq[start]+500)
                updates=f.loc[(f.seq>=seq[start])&(f.seq<endseq)].copy()
                updates["time"]=(updates.seq-seq[start])/FS
                valid=[]
                for r in updates.itertuples():
                    pos=int(np.searchsorted(seq,r.seq))
                    ok=(pos<len(seq) and seq[pos]==r.seq and pos>=WINDOW-1
                        and np.all(np.diff(seq[pos-WINDOW+1:pos+1])==1)
                        and np.isfinite(s.iloc[pos-WINDOW+1:pos+1][SIGNAL_COLUMNS].to_numpy()).all())
                    valid.append(ok)
                updates["complete"]=valid
                trials.append(dict(game=game,recording=name,trial=j+1,code=code,start=start,
                                   stop=end,start_seq=int(seq[start]),updates=updates))
            errors1=abs(f.recorded_nf-f.nf_gain1); errors2=abs(f.recorded_nf-f.nf_current_gain)
            audits.append(dict(game=game,recording=name,signal_rows=len(s),cca_updates=len(f),
                               signal_gaps=int((np.diff(seq)!=1).sum()),feature_gaps=int((np.diff(f.seq)!=HOP).sum()),
                               trials=len(trials),valid_windows=sum(t["updates"].complete.sum() for t in trials),
                               gain1_MAE=errors1.mean(),gain1_max=errors1.max(),current_gain_MAE=errors2.mean()))
            records.append(dict(game=game,name=name,signals=s,features=f,trials=trials))
    return records,pd.DataFrame(audits)

def current_windows(record,trial):
    s=record["signals"]; seq=s.seq.to_numpy()
    for row in trial["updates"].loc[trial["updates"].complete].itertuples():
        pos=int(np.searchsorted(seq,row.seq))
        yield row, s.iloc[pos-WINDOW+1:pos+1][SIGNAL_COLUMNS].to_numpy()

def psd(data):
    """Offline plotting estimator: DPSS NW=1 K=1, no padding, 1 Hz bins."""
    x=np.asarray(data,float)
    taper=signal.windows.dpss(len(x),NW=1,Kmax=1,sym=False)[0]
    return signal.periodogram(x,fs=FS,window=taper,nfft=len(x),detrend="constant",
                              scaling="density",axis=0)

def db(power): return 10*np.log10(np.maximum(power,np.finfo(float).tiny))

def heatmap(ax,matrix,title,rows=None,columns=None):
    matrix=np.asarray(matrix); lim=max(np.max(abs(matrix)),1e-30)
    im=ax.imshow(matrix,aspect="auto",cmap="RdBu_r",vmin=-lim,vmax=lim,interpolation="nearest")
    ax.set_title(f"{title}\n{matrix.shape[0]} × {matrix.shape[1]}");ax.grid(False)
    if rows is not None: ax.set_yticks(range(len(rows)),rows)
    if columns is not None: ax.set_xticks(range(len(columns)),columns,rotation=60,ha="right")
    ax.figure.colorbar(im,ax=ax,shrink=.75)
    return im

def linear_filter_demo(raw_uv):
    """Zero-state DC blocker/FIR illustration; does not replay unknown board state or glitch gating."""
    dc=signal.lfilter([1,-1],[1,-DC_R],raw_uv,axis=0)
    return signal.lfilter(FIR_TAPS[::-1],[1],dc,axis=0)
