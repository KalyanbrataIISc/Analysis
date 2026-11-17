"""Blockwise timing plots, reusable by the November 4 Leaf notebook."""
MARKDOWN='''## Timing outcomes across blocks: C1 pointing and C2 motion

Every panel uses **block 1-4 on the x-axis**. Dots are trial observations; thick curves
are medians and vertical bars are interquartile ranges, not confidence intervals.
Reaction time includes **all valid recorded responses**, irrespective of correctness,
and is measured from color reveal. Other intervals use the game's recorded event times.
Open triangles mark right-censored intervals; they do not enter observed-event medians.
The separate restricted-mean panel includes the 15-second censored tail for cue-to-reveal
and cue-to-first-green timing, allowing comparison without discarding timeout trials.
Frequency-specific plots retain the 17/19 Hz swap factor. Blocks contain 12 trials per cue,
six per attended frequency. Differences are descriptive for this participant; connecting
block summaries does not establish a learning effect.
'''
SOURCE=r'''
timing_tables=[]
for block in range(1,5):
 frame=pd.read_csv(DATA_ROOT/'gameData'/f'p7_b{block}_leaves_trialdata.csv')
 frame['block']=block;frame['cue']=frame.Cue
 frame['attended_hz']=np.where(frame.Cue.eq('c1'),frame.FrequencyC1Hz,frame.FrequencyC2Hz)
 valid=frame.ParticipantResponse.isin(['up','down','left','right']) & frame.ReactionTime.ge(0) & frame.RevealTimeout.eq(0) & frame.ResponseTimeout.eq(0)
 revealed=frame.RevealTimeout.eq(0) & frame.ColorOnsetTime.notna()
 green=frame.FirstGreenTime.notna()
 frame['rt_s']=frame.ReactionTime.where(valid)
 frame['cue_to_reveal_s']=(frame.ColorOnsetTime-frame.CueOnsetTime).where(revealed)
 frame['cue_to_green_s']=(frame.FirstGreenTime-frame.CueOnsetTime).where(green)
 frame['green_to_reveal_s']=(frame.ColorOnsetTime-frame.FirstGreenTime).where(revealed & green)
 frame['cue_to_response_s']=(frame.ColorOnsetTime+frame.ReactionTime-frame.CueOnsetTime).where(valid)
 frame['trial_duration_s']=frame.TrialEnd-frame.TrialStart
 frame['cue_to_reveal_censored_s']=(frame.TrialEnd-frame.CueOnsetTime).where(~revealed)
 frame['cue_to_green_censored_s']=(frame.TrialEnd-frame.CueOnsetTime).where(~green)
 frame['green_to_reveal_censored_s']=(frame.TrialEnd-frame.FirstGreenTime).where(~revealed & green)
 frame['cue_to_response_censored_s']=(frame.TrialEnd-frame.CueOnsetTime).where(~valid)
 frame['reveal_wait15_s']=np.minimum(frame.cue_to_reveal_s.fillna(frame.TrialEnd-frame.CueOnsetTime),15.)
 frame['green_wait15_s']=np.minimum(frame.cue_to_green_s.fillna(frame.TrialEnd-frame.CueOnsetTime),15.)
 assert frame.groupby('cue').size().eq(12).all()
 assert np.allclose(frame.loc[valid,'cue_to_response_s'],frame.loc[valid,'cue_to_reveal_s']+frame.loc[valid,'rt_s'])
 assert frame.loc[frame.RevealTimeout.eq(1),'trial_duration_s'].between(14.9,15.2).all()
 timing_tables.append(frame)
timing_trials=pd.concat(timing_tables,ignore_index=True)
TIMING_METRICS=[('rt_s','Reaction time from color reveal (s)',None),('cue_to_reveal_s','Cue to color reveal (s)','cue_to_reveal_censored_s'),('cue_to_green_s','Cue to first green (s)','cue_to_green_censored_s'),('green_to_reveal_s','First green to color reveal (s)','green_to_reveal_censored_s'),('cue_to_response_s','Cue to response (s)','cue_to_response_censored_s'),('trial_duration_s','Total trial duration (s)',None)]
def summarize_timing(keys):
 rows=[]
 for key,g in timing_trials.groupby(keys):
  if not isinstance(key,tuple):key=(key,)
  for metric,label,censor in TIMING_METRICS+[("reveal_wait15_s","Restricted cue-to-reveal waiting time (s)",None),("green_wait15_s","Restricted cue-to-first-green waiting time (s)",None)]:
   v=g[metric].dropna();row=dict(zip(keys,key))
   row.update(metric=metric,n_trials=len(g),n_observed=len(v),n_censored=int(g[censor].notna().sum()) if censor else 0,mean_s=v.mean(),median_s=v.median(),q25_s=v.quantile(.25),q75_s=v.quantile(.75),std_s=v.std())
   rows.append(row)
 return pd.DataFrame(rows)
timing_summary=summarize_timing(['block','cue'])
timing_frequency_summary=summarize_timing(['block','cue','attended_hz'])
timing_trials.to_csv(OUT/'timing_trials.csv',index=False)
timing_summary.to_csv(OUT/'timing_by_block_condition.csv',index=False)
timing_frequency_summary.to_csv(OUT/'timing_by_block_condition_frequency.csv',index=False)
fig,axes=plt.subplots(2,3,figsize=(16,9),layout='constrained')
for ax,(metric,label,censor) in zip(axes.flat,TIMING_METRICS):
 for cue,offset in [('c1',-.11),('c2',.11)]:
  summary=timing_summary[timing_summary.cue.eq(cue)&timing_summary.metric.eq(metric)].sort_values('block')
  ax.errorbar(summary.block+offset,summary.median_s,yerr=np.vstack([summary.median_s-summary.q25_s,summary.q75_s-summary.median_s]),fmt='-o',color=COLORS[cue],capsize=4,lw=2,label=cue.upper()+' median / IQR')
  for block in range(1,5):
   g=timing_trials[timing_trials.block.eq(block)&timing_trials.cue.eq(cue)]
   v=g[metric].dropna().to_numpy();jitter=np.linspace(-.045,.045,len(v))
   ax.scatter(block+offset+jitter,v,color=COLORS[cue],alpha=.4,s=23,zorder=2)
   if censor:
    cv=g[censor].dropna().to_numpy()
    ax.scatter(np.full(len(cv),block+offset+.055),cv,marker='^',facecolors='none',edgecolors=COLORS[cue],s=48,zorder=3)
   n=int(summary.loc[summary.block.eq(block),'n_observed'].iloc[0])
   ax.text(block+offset,.015 if cue=='c1' else .065,f'n={n}',transform=ax.get_xaxis_transform(),ha='center',fontsize=8,color=COLORS[cue])
 ax.set(xlabel='Block',ylabel=label,xticks=[1,2,3,4],xlim=(.65,4.35));ax.legend(fontsize=8,loc='upper left',bbox_to_anchor=(0,1.02),ncol=2,frameon=False)
savefig(fig,'timing_across_blocks_c1_c2','Timing across blocks: C1 pointing and C2 motion','Every panel uses block on the x-axis. Dots: individual trials; lines: medians; bars: IQR. Open triangles: right-censored intervals, excluded from observed-event medians. Reaction times include all valid responses, independent of accuracy. n labels give observed values per cue/block.')
fig,axes=plt.subplots(2,3,figsize=(16,9),layout='constrained')
for row,cue in enumerate(['c1','c2']):
 for col,(metric,label,censor) in enumerate(TIMING_METRICS[:3]):
  ax=axes[row,col]
  for hz,color,ls,offset in [(17.,'#009E73','-',-.08),(19.,'#CC79A7','--',.08)]:
   ss=timing_frequency_summary[timing_frequency_summary.cue.eq(cue)&timing_frequency_summary.attended_hz.eq(hz)&timing_frequency_summary.metric.eq(metric)].sort_values('block')
   ax.errorbar(ss.block+offset,ss.median_s,yerr=np.vstack([ss.median_s-ss.q25_s,ss.q75_s-ss.median_s]),marker='o',ls=ls,color=color,capsize=3,label=f'Attend {hz:g} Hz')
   for block in range(1,5):
    g=timing_trials[timing_trials.block.eq(block)&timing_trials.cue.eq(cue)&timing_trials.attended_hz.eq(hz)]
    v=g[metric].dropna().to_numpy();ax.scatter(block+offset+np.linspace(-.03,.03,len(v)),v,s=19,color=color,alpha=.4)
    if censor:
     cv=g[censor].dropna().to_numpy();ax.scatter(np.full(len(cv),block+offset+.04),cv,marker='^',facecolors='none',edgecolors=color,s=42)
  ax.set(title=cue.upper(),xlabel='Block',ylabel=label,xticks=[1,2,3,4],xlim=(.65,4.35));ax.legend(fontsize=8)
savefig(fig,'timing_across_blocks_frequency','Timing across blocks separated by attended frequency','C1 top row; C2 bottom row. Six trials per cue x frequency x block. Lines: observed-event median; bars: IQR; dots: individual trials; open triangles: censored. All valid reaction times are included.')
fig,axes=plt.subplots(1,2,figsize=(12,5),layout='constrained')
rng=np.random.default_rng(20261104)
restricted_rows=[]
for ax,metric,label in zip(axes,['reveal_wait15_s','green_wait15_s'],['Cue-to-reveal restricted waiting time at 15 s (s)','Cue-to-first-green restricted waiting time at 15 s (s)']):
 for cue,offset in [('c1',-.07),('c2',.07)]:
  means=[];lows=[];highs=[]
  for block in range(1,5):
   g=timing_trials[timing_trials.block.eq(block)&timing_trials.cue.eq(cue)]
   by_hz=[g.loc[g.attended_hz.eq(hz),metric].to_numpy() for hz in [17.,19.]]
   draws=np.mean([rng.choice(v,(2000,len(v)),replace=True).mean(1) for v in by_hz],axis=0)
   mean=g[metric].mean();lo,hi=np.quantile(draws,[.025,.975]);means.append(mean);lows.append(lo);highs.append(hi)
   restricted_rows.append(dict(block=block,cue=cue,metric=metric,n_trials=len(g),restricted_mean_s=mean,ci_low_s=lo,ci_high_s=hi))
  xx=np.arange(1,5)+offset;ax.plot(xx,means,'-o',color=COLORS[cue],label=cue.upper());ax.fill_between(xx,lows,highs,color=COLORS[cue],alpha=.16)
 ax.set(xlabel='Block',ylabel=label,xticks=[1,2,3,4],xlim=(.7,4.3),ylim=(0,15.5));ax.legend()
pd.DataFrame(restricted_rows).to_csv(OUT/'restricted_timing_by_block.csv',index=False)
savefig(fig,'restricted_timing_across_blocks','Timing across blocks including administrative timeouts','All 12 trials per cue/block contribute. Right-censored waiting times contribute the known 15-second tail to restricted means. Shading: 95% trial-bootstrap intervals, resampling within attended-frequency cells; conditional on this participant and block.')
display(timing_summary.pivot_table(index=['block','cue'],columns='metric',values='median_s').round(3))
print('Timing checked: 96 trials; RT includes all valid recorded responses; censored intervals reported separately.')
'''
