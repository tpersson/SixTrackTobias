!FOX  Y(1)=Y(1)-X(2)*ED(IX) ;
!FOX  Y(2)=Y(2)+X(1)*ED(IX) ;
!FOX  CRKVE=Y(1)-X(1)*ED(IX)*EK(IX) ;
!FOX  CIKVE=Y(2)-X(2)*ED(IX)*EK(IX) ;
!FOX  Y(1)=CRKVE*COS(EK(IX))+CIKVE*SIN(EK(IX)) ;
!FOX  Y(2)=-CRKVE*SIN(EK(IX))+CIKVE*COS(EK(IX)) ;
!FOX  CRKVE=X(1)*COS(EK(IX))+X(2)*SIN(EK(IX)) ;
!FOX  CIKVE=-X(1)*SIN(EK(IX))+X(2)*COS(EK(IX)) ;
!FOX  X(1)=CRKVE ;
!FOX  X(2)=CIKVE ;
!FOX  Y(1)=Y(1)+X(2)*ED(IX) ;
!FOX  Y(2)=Y(2)-X(1)*ED(IX) ;