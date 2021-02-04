#requires jq to be installed
SERVER_ADDRESS="http://192.168.1.255:8111"
USERNAME="default"
PASSWORD="test123"
#do not include trailing slash in LOCAL_PATH or MEDIA_SERVER_PATH
#LOCAL_PATH is the anime path in perspective of this machine
LOCAL_PATH="/path/to/anime"
#MEDIA_SERVER_PATH is the anime path in perspective of emby/jellyfin
MEDIA_SERVER_PATH="/data/Anime" #NEEDS TO BE XML SAFE

API_KEY=$(curl -s ''$SERVER_ADDRESS'/api/auth'   -H 'Accept: application/json'   -H 'Content-Type: application/json'   --data-binary '{"user":"'$USERNAME'","pass":"'$PASSWORD'","device":"web-ui","rememberUser":false}' |jq '.apikey'| tr -d '"')

#SERVER_PATH=$(curl -s ''$SERVER_ADDRESS'/api/v3/ImportFolder/'   -H 'Accept: application/json'   -H 'apikey: '$API_KEY''   -H 'Content-Type: application/json' |jq '.[]|select(.DropFolderType==2)|.Path')


IFS=$'\n'
for d in $(find $LOCAL_PATH -maxdepth 1 -mindepth 1 -type d -printf '%f\n' |sort); do
    #echo $d
	rm -f /tmp/episode_plexdata
	rm -f /tmp/series_plexdata
	rm -f /tmp/series_plexfulldata
	
    for f in $(find $LOCAL_PATH/$d  -maxdepth 1 -mindepth 1 -type f \( -iname "*mp4" -o -iname "*.mkv" -o -iname "*avi" -o -iname "*ogm" \) -printf '%f\n' |sort); do
        #echo $f
        f_encoded=$(jq -R -r @uri <<<"$f")
		f_noext=$(echo $f | grep -oP '.+(?=\.)')
		EPISODE_NFO_LOCATION="$LOCAL_PATH/$d/$f_noext.nfo"
		
		#echo $f
		#echo ./$d/$f
        curl -s ''$SERVER_ADDRESS'/api/ep/getbyfilename?filename='$f_encoded'&apikey='$API_KEY'' > /tmp/episode_plexdata
        
        EPISODE_ID=$(cat /tmp/episode_plexdata | jq '.id')
        curl -s ''$SERVER_ADDRESS'/api/serie/fromep?id='$EPISODE_ID'&nocast=1&notag=1&apikey='$API_KEY'' > /tmp/series_plexdata
        SERIES_TITLE=$(cat /tmp/series_plexdata | jq -r '.name'|sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g') 
        SERIES_ID=$(cat /tmp/series_plexdata | jq '.id') 
        
        
        EPISODE_TYPE=$(cat /tmp/episode_plexdata | jq -r '.eptype')
        if [ $EPISODE_TYPE = "Credits" ]; then 
            SEASON="-1"
        elif [ $EPISODE_TYPE = "Trailer" ]; then
            SEASON="-2"
        #elif [ $EPISODE_TYPE = "Special" ]; then
        #    SEASON="0"
        else
            SEASON=$(cat /tmp/episode_plexdata | jq '.season' |grep -oP '\d+(?=x)')
        fi 
        
        EPISODE_TITLE=$(cat /tmp/episode_plexdata | jq -r '.name'|sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
        RATINGS=$(cat /tmp/episode_plexdata | jq -r '.rating')
        RATINGS_VOTES=$(cat /tmp/episode_plexdata | jq -r '.votes')
        EPISODE_NUM=$(cat /tmp/episode_plexdata | jq -r '.epnumber')
        PLOT=$(cat /tmp/episode_plexdata | jq -r '.summary'|sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
        YEAR=$(cat /tmp/episode_plexdata | jq -r '.year')
        AIRED=$(cat /tmp/episode_plexdata | jq -r '.air')
        
        THUMB_URL=$(cat /tmp/episode_plexdata | jq -r '.art.thumb[0].url')
		THUMB="$f_noext-thumb.jpg"
		
        THUMB_LOCATION="$LOCAL_PATH/$d/$THUMB"
        
        curl -s ''$SERVER_ADDRESS'/api/v3/Episode/'$EPISODE_ID''   -H 'Accept: application/json'   -H 'apikey: '$API_KEY''   -H 'Content-Type: application/json' > /tmp/episodeinfo
        
        EPISODE_ANIDB_ID=$(cat /tmp/episodeinfo|jq '.IDs.AniDB')
        EPISODE_TVDB_ID=$(cat /tmp/episodeinfo|jq '.IDs.TvDB[]?')
        
        ###############################
        #   GENERATE NFO FOR EPISODE  #
        ###############################
       echo '<episodedetails>' 							 > $EPISODE_NFO_LOCATION
       echo '  <title>'$EPISODE_TITLE'</title>' 		>> $EPISODE_NFO_LOCATION
       echo '  <showtitle>'$SERIES_TITLE'</showtitle>' 	>> $EPISODE_NFO_LOCATION
       echo '  <season>'$SEASON'</season>' 				>> $EPISODE_NFO_LOCATION
       echo '  <episode>'$EPISODE_NUM'</episode>' 		>> $EPISODE_NFO_LOCATION
       echo '  <aired>'$AIRED'</aired>' 				>> $EPISODE_NFO_LOCATION
       echo '  <plot>'$PLOT'</plot>' 					>> $EPISODE_NFO_LOCATION
       echo '  <rating>' 								>> $EPISODE_NFO_LOCATION
       echo '	  <value>'$RATINGS'</value>' 			>> $EPISODE_NFO_LOCATION
       echo '	  <votes>'$RATINGS_VOTES'</votes>' 		>> $EPISODE_NFO_LOCATION
       echo '  </rating>' 								>> $EPISODE_NFO_LOCATION
       echo '  <uniqueid type="anidb" default="true">'$EPISODE_ANIDB_ID'</uniqueid>' 	>> $EPISODE_NFO_LOCATION
       if [ "$EPISODE_TVDB_ID" != "" ]; then
       echo '  <uniqueid type="tvdb">'$EPISODE_TVDB_ID'</uniqueid>' 	>> $EPISODE_NFO_LOCATION
       fi
       echo '</episodedetails>' 						>> $EPISODE_NFO_LOCATION
       wget -q $SERVER_ADDRESS$THUMB_URL -O "$THUMB_LOCATION"
	   #echo $d/$f_noext
	   #echo wget $SERVER_ADDRESS$THUMB_URL -O ./$d/$THUMB
    done
   	SERIES_NFO_LOCATION="$LOCAL_PATH/$d"
    curl -s ''$SERVER_ADDRESS'/api/serie?id='$SERIES_ID'&level=3&allpics=1&apikey='$API_KEY'' > /tmp/series_plexfulldata
    #SERIES_TITLE == tvshow == title == originaltitle
    SERIES_ORIGINALTITLE=$(cat /tmp/series_plexfulldata |jq -r '.titles[]|select(.Language=="en")|select(.Type=="official")|.Title' | tr -d '"'|sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
    SERIES_RATINGS=$(cat /tmp/series_plexfulldata |jq -r '.rating')
    SERIES_RATINGS_VOTES=$(cat /tmp/series_plexfulldata |jq -r '.votes')
    SERIES_PLOT=$(cat /tmp/series_plexfulldata |jq -r '.summary'|sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
    SERIES_PREMIERED=$(cat /tmp/series_plexfulldata |jq -r '.air')
    SERIES_YEAR=$(cat /tmp/series_plexfulldata |jq -r '.year')
    SERIES_GENRES=$(cat /tmp/series_plexfulldata |jq -r '.tags[]?'|sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
    SERIES_FANART_URL=$(cat /tmp/series_plexfulldata| jq -r '.art.fanart[0].url')
    SERIES_POSTER_URL=$(cat /tmp/series_plexfulldata| jq -r '.art.thumb[0].url')
    
    echo $SERIES_ID    $SERIES_TITLE  
    curl -s ''$SERVER_ADDRESS'/api/v3/Series/'$SERIES_ID''   -H 'Accept: application/json'   -H 'apikey: '$API_KEY''   -H 'Content-Type: application/json' > /tmp/seriesinfo
        
    ANIDB_ID=$(cat /tmp/seriesinfo|jq '.IDs.AniDB')
    TVDB_ID=$(cat /tmp/seriesinfo|jq '.IDs.TvDB[]?')
    MAL_ID=$(cat /tmp/seriesinfo|jq '.IDs.MAL[]')
        
        
        
    #echo anidb: $ANIDB_ID   TVDB: $TVDB_ID     MAL:$MAL_ID
    
    ###############################
    #   GENERATE NFO FOR SERIES   #
    ###############################
   echo '<tvshow>' 										 > $SERIES_NFO_LOCATION/tvshow.nfo
   echo '  <title>'$SERIES_TITLE'</title>' 				>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '  <originaltitle>'$SERIES_ORIGINALTITLE'</originaltitle>' 	>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '  <rating>' 									>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '	  <value>'$SERIES_RATINGS'</value>' 		>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '	  <votes>'$SERIES_RATINGS_VOTES'</votes>' 	>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '  </rating>' 									>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '  <plot>'$SERIES_PLOT'</plot>' 				>> $SERIES_NFO_LOCATION/tvshow.nfo
   #echo '  <Genres>'                     				>> $SERIES_NFO_LOCATION/tvshow.nfo
   for i in $SERIES_GENRES; do 
       echo '   <genre>'$i'</genre>' 						>> $SERIES_NFO_LOCATION/tvshow.nfo
   done
   #echo '  </Genres>'                     				>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '  <premiered>'$SERIES_PREMIERED'</premiered>' 	>> $SERIES_NFO_LOCATION/tvshow.nfo
   echo '  <year>'$SERIES_YEAR'</year>' 				>> $SERIES_NFO_LOCATION/tvshow.nfo
   
   echo '  <uniqueid type="anidb" default="true">'$ANIDB_ID'</uniqueid>' 	>> $SERIES_NFO_LOCATION/tvshow.nfo
   if [ "$TVDB_ID" != "" ]; then
       echo '  <uniqueid type="tvdb">'$TVDB_ID'</uniqueid>' 	>> $SERIES_NFO_LOCATION/tvshow.nfo
   fi
   #if [ "$MAL_ID" != "" ]; then
   #echo '  <uniqueid type="mal">'$MAL_ID'</uniqueid>' 	>> $SERIES_NFO_LOCATION/tvshow.nfo
   #fi
   echo '</tvshow>' 									>> $SERIES_NFO_LOCATION/tvshow.nfo
   
   wget -q $SERVER_ADDRESS$SERIES_FANART_URL -O "$SERIES_NFO_LOCATION/fanart.jpg"
   wget -q $SERVER_ADDRESS$SERIES_POSTER_URL -O "$SERIES_NFO_LOCATION/poster.jpg"
   #echo wget $SERVER_ADDRESS$SERIES_FANART_URL -O ./$d/fanart.jpg
   #echo wget $SERVER_ADDRESS$SERIES_POSTER_URL -O ./$d/poster.jpg
    
    curl -s ''$SERVER_ADDRESS'/api/v3/Series/'$SERIES_ID'/Group'   -H 'Accept: application/json'   -H 'apikey: '$API_KEY''   -H 'Content-Type: application/json' > /tmp/group_info
	#echo curl -s ''$SERVER_ADDRESS'/api/v3/Series/'$SERIES_ID'/Group'   -H 'Accept: application/json'   -H 'apikey: '$API_KEY''   -H 'Content-Type: application/json' 
    GROUP_ID=$(cat /tmp/group_info |jq '.IDs.ID')
    GROUP_NAME=$(cat /tmp/group_info |jq -r '.Name')
    
    #echo $GROUP_ID         $GROUP_NAME
    
    ###############################
    # APPEND SERIES TO COLLECTION #
    ###############################
    COLLECTION_FOLDER="$GROUP_NAME [boxset]"
    COLLECTION_FOLDER=$(echo $COLLECTION_FOLDER | tr / \\ 2> /dev/null)
    d=$(echo $d|sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
	if [ ! -d "$COLLECTION_FOLDER" ]; then
		mkdir ""$COLLECTION_FOLDER""
		#echo mkdir ""$COLLECTION_FOLDER""
	fi
	#COLLECTION_FOLDER=$(echo $COLLECTION_FOLDER |sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
	
	GROUP_NAME=$(echo $GROUP_NAME |sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
	if [ -f "$COLLECTION_FOLDER/collection.xml" ];then 
		head -n -2 "$COLLECTION_FOLDER/collection.xml" > temp.txt ; mv temp.txt "$COLLECTION_FOLDER/collection.xml"
		echo "Adding to existing collection.xml"
	else
		echo '<Item>' 														     > "$COLLECTION_FOLDER/collection.xml"
		echo '	<Added>'$(date +"%m/%d/%Y %r")'</Added>' 					    >> "$COLLECTION_FOLDER/collection.xml"
		echo '	<LockData>false</LockData>' 								    >> "$COLLECTION_FOLDER/collection.xml"
		echo '	<LocalTitle>'$GROUP_NAME'</LocalTitle>' 						>> "$COLLECTION_FOLDER/collection.xml"
		echo '	<Genres>' 													    >> "$COLLECTION_FOLDER/collection.xml"
		for i in $SERIES_GENRES; do 
			echo '		<Genre>'$i'</Genre>' 								    >> "$COLLECTION_FOLDER/collection.xml"
		done
		echo '	</Genres>' 													    >> "$COLLECTION_FOLDER/collection.xml"
		#echo '	<Studios>' 													    >> "$COLLECTION_FOLDER/collection.xml"
		#echo '		<Studio>Sunrise</Studio>'								    >> "$COLLECTION_FOLDER/collection.xml"
		#echo '	</Studios>' 												    >> "$COLLECTION_FOLDER/collection.xml"
		echo '	<DisplayOrder>PremiereDate</DisplayOrder>' 					    >> "$COLLECTION_FOLDER/collection.xml"
		echo '	<CollectionItems>' 											    >> "$COLLECTION_FOLDER/collection.xml"
	fi
	
	echo '		<CollectionItem>' 										>> "$COLLECTION_FOLDER/collection.xml"
	echo '			<Path>'$MEDIA_SERVER_PATH'/'$d'</Path>' 			>> "$COLLECTION_FOLDER/collection.xml"
	echo '	    </CollectionItem>' 										>> "$COLLECTION_FOLDER/collection.xml"
	echo '	</CollectionItems>' 										>> "$COLLECTION_FOLDER/collection.xml"
	echo '</Item>' 														>> "$COLLECTION_FOLDER/collection.xml"
	
	if [ ! -f "$COLLECTION_FOLDER/fanart.jpg" ];then
        cp "$SERIES_NFO_LOCATION/fanart.jpg" "$COLLECTION_FOLDER"
        cp "$SERIES_NFO_LOCATION/poster.jpg" "$COLLECTION_FOLDER"
	fi
done

