void canonical2emittance_(double cancord[6], double emittance[3]);

void dist2sixcoord_();
void action2canonical_(double acangl[6], double cancord[6]);
void action2sixinternal_(double tc[6], double *results);
int checkdist();
void change_e3_to_dp_easy(double cancord[6], double acoord[6], double acangl[6]);
double opemitt(double cancord[6], double acoord[6], double acangl[6], double x);
double optideltas(double cancord[6], double acoord[6], double acangl[6], double x);
double createrandom(double insigma[6], double cancord[6]);
double toactioncord_(double cancord[6], double acoord[6], double acangl[6]);