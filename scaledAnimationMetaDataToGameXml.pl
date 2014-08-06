#!/usr/bin/env perl

#Copyright (c) 2013, Stargazy Studios
#All Rights Reserved

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Stargazy Studios nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#This script merges animation data from Spriter SCML (b5 version used as reference, and 
#texture atlas information from Texture Packer's generic XML output, creating XML 
#conforming to gameXml.xsd. The script assumes that both sets of input data were created 
#at the same location in the file system, with the same directory structure and file 
#naming below it.

#As per gameXml.xsd, the script finds or creates gameConfig root element, and outputs 
#scaledArtIndex sub elements underneath it. scaledArtIndex elements contain animation and 
#texture atlas information. Other than these elements, gameXml.xsd can be altered to suit 
#a project's static data requirements.

#The output of the script replaces any existing animation data in an input gameXml 
#document.

#The current output format is tailored to represent frame-by-frame animations, dropping  
#transformation, tweening, and bone data created in Spriter. However, the interim logic 
#between reading the input XML files, and outputting merged XML, stores all data in easily
# navigable structures. These can be expanded to hold additional Spriter element types, 
#and also be output with a custom logic loop, using an alternative output format.

#Parameters for the script are passed as XML, conforming to scaledAnimationMetaData.xsd.

#Recommended software for visually editing XML schema: 
#	XML Seed (http://www.xmlseed.com/)
#Recommended software for editing/creating XML documents from an XSD schema:
#	XAmple (http://freecode.com/projects/xample)

use warnings;
use strict;
use warnings;
use Getopt::Long;
use XML::LibXML;
use Data::Dumper;
use File::Basename;

#Read in file parameters.
my $paramIn = '';	#xml file conforming to scaledAnimationMetaData.xsd
my $animGuidCount = 0;
my $animFrameGuidCount = 0;

GetOptions(	'paramIn=s' => \$paramIn,
			'frameGuidStart=i' => \$animFrameGuidCount,
			'animGuidStart=i' => \$animGuidCount);

#Create LibXML data structures to store input documents.
my $parserLibXML = XML::LibXML->new('no_blanks' => 1); #flatten indentation

if(-e $paramIn){
	#print "DEBUG: parameter file: $paramIn\n";
	my $paramDoc = $parserLibXML->parse_file($paramIn);
	
	#validate paramDoc with scaledAnimationMetaData.xsd
	if(-e "scaledAnimationMetaData.xsd"){
		my $scaledAnimationMetaDataSchema = XML::LibXML::Schema->new('location' => "scaledAnimationMetaData.xsd");
		eval {$scaledAnimationMetaDataSchema->validate($paramDoc);};
		die $@ if $@;
	}
	else{
		print "WARNING: scaledAnimationMetaData.xsd could not be found to validate ".
		"$paramIn file.\n";
	}
	
	#Create hash tables to hold frame name GUID & animation name GUID lookups.
	#N.B. Spriter does not give each file a GUID, but a UID under a folder UID. 
	#Sequential integer GUIDs will be stored in the unique path/filename keyed hash.

	my %frameFileNameToGuid = (); 		#holds file name keyed hash of GUIDs.
	my @guidToFrameFileName = ();		#holds GUID indexed file names.
	
	my @animations = ();				#holds all animation data: 
										#[guid]	[	name,	
										#			[	frame GUID, 
										#				frame start time,
										#				frame end time, 
										#				frame translate x,
										#				frame translate y
										#			],
										#			length
										#		]
	my $runtimeTextureDirectory = "";	#holds any specified string to override the 
										#directory for texture files
	my @textureFiles = ();				#holds all texture file data:
										#[	scale factor,
										#	target pixel density,
										#	target resolution x,
										#	target resolution y,
										#	{fileLocation}	[
										#						[	frame GUID,
										#							frame u,
										#							frame v,
										#							frame width,
										#							frame height
										#						]
										#	]
										#]
										# N.B. discards original component file name information

	#************* For each Spriter document. *************#
	
	foreach my $spriterFileElement ($paramDoc->getElementsByTagName('spriterFile')){
		my $spriterFileName = $spriterFileElement->textContent;
		my $spriterDoc = $parserLibXML->parse_file($spriterFileName);
		
		#TODO: validate SCML if and when a schema is made available
		
		if ($spriterDoc){
			my %spriterFrameIdToGuid = (); 	#keyed by folder id, storing hash keyed by file id, which 
											#temporarily holds the frame GUID.
			
			#Parse Spriter "file" elements to populate frame name hash.
			foreach my $spriterFolderElement ($spriterDoc->getElementsByTagName('folder')){
				
				my $folderId = "";
				my $fileId = "";
				my $fileName = "";
				
				if($spriterFolderElement->hasAttribute("id")){
					$folderId = $spriterFolderElement->getAttribute("id");
				}
				else{
					print "ERROR: Missing Spriter folder \"id\" attribute\n";
					exit 1;
				}
				
				foreach my $spriterFileElement ($spriterFolderElement->getChildrenByTagName('file')){		
					if($spriterFileElement->hasAttribute("name")){
						if($spriterFileElement->hasAttribute("id")){
					
							#name includes directory path
							$fileName = $spriterFileElement->getAttribute("name");
							$fileId = $spriterFileElement->getAttribute("id");
				
							if(exists $frameFileNameToGuid{$fileName}){
								#assume that we are processing a new Spriter document, 
								#with its own set of UIDs, and overwrite existing, but 
								#leave our frame GUID intact
								$spriterFrameIdToGuid{$folderId}{$fileId} = $frameFileNameToGuid{$fileName};								
							}
							else{ #generate new frame GUID for sprite file
								$frameFileNameToGuid{$fileName} = $animFrameGuidCount;
								$guidToFrameFileName[$animFrameGuidCount] = $fileName;
								
								$spriterFrameIdToGuid{$folderId}{$fileId} = $animFrameGuidCount;
								
								$animFrameGuidCount++;
							}
						}
						else{
							print "ERROR: Missing Spriter file \"id\" attribute\n";
							exit 1;			
						}
					}
					else{
						print "ERROR: Missing Spriter file \"name\" attribute\n";
						exit 1;			
					}
				}
			}

			#Parse Spriter "animation" types to create named animations & generate  
			#animation GUIDs.
			foreach my $spriterAnimationElement ($spriterDoc->getElementsByTagName('animation')){
				#print "DEBUG: processing \"animation\" in Spriter file\n";
				my $animName = "";
				my $animLength = 0; #time in milliseconds
				
				if(	$spriterAnimationElement->hasAttribute("name") &&
					$spriterAnimationElement->hasAttribute("length")){
					$animName = $spriterAnimationElement->getAttribute("name");
					$animLength = $spriterAnimationElement->getAttribute("length");
					#print "DEBUG: \"animation\" has a name: $animName\n";

					#N.B. Spriter b5 SCML is difficult to read for frame-by-frame 
					#animations. It does not indicate where the frame starts and stops, 
					#just the key frame timings. As it happens, the first key is the entry 
					#time, and the second is the exit time, so the duration of the frame 
					#can be derived from this. Subsequent start/stop pairs of the same 
					#object can occur if it is reused under the same animation. Processing
					#the 'key' elements in order is important to preserve this meaning.
					
					#UPDATE: Spriter b6 has changed its SCML format, now we must interpret
					#it differently. The "timeline" elements no longer contain two "key" 
					#elements (with  a start and a stop time). There is now only one "key"
					#that has the start time contained in it. The "mainline" element 
					#contains the timing information, where the absence of an object at 
					#a specific "key", means that it has been removed at that time.
	
					#create array of arrays holding key elements, indexed by timeline then
					#id: @{$timelineKeys[$timelineId][$keyId]} = [	$frameGuid,
					#												$frameTranslateX,
					#												$frameTranslateY ]
					my @timelineKeys = (); 					
					foreach my $timelineCandidate ($spriterAnimationElement->getChildrenByTagName('timeline')){
						
						#print "DEBUG: processing \"timeline\" in Spriter file\n";
						my $timelineId = "";
						
						if($timelineCandidate->hasAttribute("id")){
							$timelineId = $timelineCandidate->getAttribute("id");
							
							foreach my $keyCandidate ($timelineCandidate->getChildrenByTagName('key')){
								if($keyCandidate->hasAttribute("id")){
									my $keyId = $keyCandidate->getAttribute("id");
								
									my $frameGuid = "";
									my $frameFolderId = "";
									my $frameFileId = "";
									my $frameTranslateX = "";
									my $frameTranslateY = "";
											
									my $objectCandidate = '';
									my @objects = $keyCandidate->getChildrenByTagName('object');
									my $numObjects = @objects;
									if($numObjects){$objectCandidate = $objects[0]}; #only expecting one object
							
									if($objectCandidate){
										if(	$objectCandidate->nodeName eq "object" &&
											$objectCandidate->hasAttribute("folder") &&
											$objectCandidate->hasAttribute("file") &&
											$objectCandidate->hasAttribute("x") &&
											$objectCandidate->hasAttribute("y")){						
									
											#store object file and folder id
											$frameFolderId = $objectCandidate->getAttribute("folder");
											$frameFileId = $objectCandidate->getAttribute("file");
									
											#store location coordinates of animation frame translate 
											$frameTranslateX = $objectCandidate->getAttribute("x");
											$frameTranslateY = $objectCandidate->getAttribute("y");
										}
										else{
											print "ERROR: Missing Spriter \"object\", or its attributes in ".
											"first \"key\" in animation $animName\n";
											exit 1;
										}
									}
									else{
										print "ERROR: Missing Spriter file \"object\" node in first \"key\" ".
										"in animation $animName\n";
										exit 1;
									}
													
									#lookup frame GUID using folder and file attributes
									if($frameFolderId >= 0 && $frameFileId >= 0){
										if(exists $spriterFrameIdToGuid{$frameFolderId}{$frameFileId}){
											$frameGuid = $spriterFrameIdToGuid{$frameFolderId}{$frameFileId};
										}
										else{
											print "ERROR: Missing Spriter frame GUID for ($frameFolderId,$frameFileId)". 
											"[folder id, file id] in animation $animName\n";
											exit 1;
										}
									}
									else{
										print "ERROR: Missing Spriter file or folder id for frame ". 
										"in animation $animName, when trying to look up frame GUID\n";
										exit 1;
									}
										
									#DEBUG
									#print "DEBUG: storing timeLineKey\n";
									#store timeline key data
									$timelineKeys[$timelineId][$keyId] = [	$frameGuid,
																			$frameTranslateX,
																			$frameTranslateY ];
								}
							
							}
						}
						else{
							print "ERROR: Missing id attribute for timeline element ". 
							"in animation $animName.\n";
							exit 1;
						}
					}
					
					#DEBUG
					#print "timelineKeys for $animName: \n".Dumper(@timelineKeys);
					
					#process "mainline" element; N.B. there should only be one
					#store key data in hash, keyed by each key's time:
					#%mainlineKeys{$keyTime} = [	$object_refTimeline,
					#								$object_refKey ]
					my %mainlineKeys;
					foreach my $mainlineCandidate ($spriterAnimationElement->getChildrenByTagName('mainline')){
						%mainlineKeys = (); #override any existing data in the hash
						
						foreach my $keyCandidate($mainlineCandidate->getChildrenByTagName('key')){
							my $keyTime = 0;
							
							if($keyCandidate->nodeName eq "key"){						
								if($keyCandidate->hasAttribute("time")){
									$keyTime = $keyCandidate->getAttribute("time");
								}

								my $object_refCandidate = '';
								my @object_refs = $keyCandidate->getChildrenByTagName('object_ref');
								my $numObject_refs = @object_refs;
								
								my $object_refTimeline = "";
								my $object_refKey = "";
								
								for(my $j = 0; $j < $numObject_refs; $j++){
									$object_refCandidate = $object_refs[$j];
									if($object_refCandidate->hasAttribute("timeline")){
										$object_refTimeline = $object_refCandidate->getAttribute("timeline");
									}
									if($object_refCandidate->hasAttribute("key")){
										$object_refKey = $object_refCandidate->getAttribute("key");
									}
									
									if(	$object_refTimeline ne "" &&
										$object_refKey ne ""){
										#DEBUG
										#print "DEBUG: storing mainlineKey\n";
										push(@{$mainlineKeys{$keyTime}},[$object_refTimeline, $object_refKey]);
									}
								}
							}
						}
					}
					
					#DEBUG
					#print "mainlineKeys for $animName: \n".Dumper(%mainlineKeys);

					#temporary list of active frames:
					#@{$activeFrames{timelineId}{keyId} = [frameStartTime,frameEndTime]
					my %activeFrames = ();
					foreach my $mainlineTime (sort keys %mainlineKeys){
						foreach my $object_ref (@{$mainlineKeys{$mainlineTime}}){
							my $timeLineId = @$object_ref[0];
							my $keyId = @$object_ref[1];
							
							#frame newly introduced to mainline
							if (!exists $activeFrames{$timeLineId}{$keyId}){
								#DEBUG
								#print "DEBUG: starting activeFrame using frameStartTime = mainlineTime\n";
								$activeFrames{$timeLineId}{$keyId} = [$mainlineTime,$mainlineTime];
							}
							#existing frame continues to be displayed, so update frameEndTime
							else{
								#DEBUG
								#print "DEBUG: updating activeFrame frameEndTime = mainlineTime\n";
								$activeFrames{$timeLineId}{$keyId}[1] = $mainlineTime;
							}
							
							#check for frames that have not had their end times updated to the current time,
							#and output those completed frames to the animation array
							for my $checkTimelineId (keys %activeFrames){
								for my $checkKeyId (keys %{$activeFrames{$checkTimelineId}}){									
										if ($activeFrames{$checkTimelineId}{$checkKeyId}[1] != $mainlineTime){
											#DEBUG
											#print "DEBUG: storing activeFrame using frameEndTime = mainlineTime\n";
											#store animation frame timings and frame translates
											push(	@{$animations[$animGuidCount][1]},
													[	$timelineKeys[$checkTimelineId][$checkKeyId][0],	#frameGuid
														$activeFrames{$checkTimelineId}{$checkKeyId}[0],	#frameStartTime
														$mainlineTime,										#frameEndTime
														$timelineKeys[$checkTimelineId][$checkKeyId][1],	#frameTranslateX
														$timelineKeys[$checkTimelineId][$checkKeyId][2] 	#frameTranslateY
													]);
											delete $activeFrames{$checkTimelineId}{$checkKeyId};
										}	
								}
							}
						}
					}
					
					#for all frames that have not exited at a key frame, set their end time to the animation
					#length
					for my $timelineId (keys %activeFrames){
						for my $keyId (keys %{$activeFrames{$timelineId}}){
							#DEBUG
							#print "DEBUG: storing activeFrame using frameEndTime = animLength\n";
							#store animation frame timings and frame translates
							push(	@{$animations[$animGuidCount][1]},
									[	$timelineKeys[$timelineId][$keyId][0],	#frameGuid
										$activeFrames{$timelineId}{$keyId}[0],	#frameStartTime
										$animLength,							#frameEndTime
										$timelineKeys[$timelineId][$keyId][1],	#frameTranslateX
										$timelineKeys[$timelineId][$keyId][2] 	#frameTranslateY
									]);
						}	
					}
					
					my $animFrameCount = @{$animations[$animGuidCount][1]};
					#print "DEBUG: number of animations frames for $animName: $animFrameCount\n";
					if($animFrameCount){ 
						#store animation name & length
						$animations[$animGuidCount][0] = $animName;
						$animations[$animGuidCount][2] = $animLength;
						
						#sort animation frame timings by start time (already sorted by end time)
						@{$animations[$animGuidCount][1]} = sort {$a->[1]<=>$b->[1]} @{$animations[$animGuidCount][1]};
						
						$animGuidCount++;
					}
					else{ #animation is empty, do not increment animation GUID, & overwrite on next valid animation
						print "WARNING: Empty Spriter animation $animName will not be stored\n";
						#clear references to temporarily stored data
						$animations[$animGuidCount][1] = ();
						$animations[$animGuidCount] = ();
					}
				}			

				else{
					print "ERROR: Missing Spriter animation \"name\" or \"length\" attribute\n";
					exit 1;	
				}
			}
		}
		else{
			print "WARNING: Could not parse Spriter file $spriterFileName\n";
		}
		#DEBUG
		#print Dumper(@animations);
	}
	
	#DEBUG
	#print Dumper(%frameFileNameToGuid);
	
	#************* For each runtime texture directory string. *************#
	foreach my $runtimeTextureDirectoryElement ($paramDoc->getElementsByTagName('runtimeTextureDirectory')){
		#N.B. there should only be one element at most
		$runtimeTextureDirectory = $runtimeTextureDirectoryElement->textContent;
	}
	#check non-empty directory finishes with a slash if it contains one.
	#N.B. the runtime file system may differ from the script's environment, so we can not simply use File::Spec
	if(length($runtimeTextureDirectory) && $runtimeTextureDirectory !~ /^.*[\/\\]$/){ #check directory does not end with a slash
		if($runtimeTextureDirectory =~ /^.*[\/].*$/){$runtimeTextureDirectory = "$runtimeTextureDirectory/";} #check if it contains a forward slash
		elsif($runtimeTextureDirectory =~ /^.*[\\].*[^\\]$/){$runtimeTextureDirectory = "$runtimeTextureDirectory\\";} #check if it contains a back slash
	}
	
	#************* For each scaled TexturePacker file. *************#
	my $scaleCount = 0;
	foreach my $scaledTexturePackerFileElement ($paramDoc->getElementsByTagName('scaledTexturePackerFiles')){
		
		#scale factor is required in schema
		my $scaleFactor = ($scaledTexturePackerFileElement->getElementsByTagName('scaleFactor'))[0]->textContent;
		
		#optional asset target resolution data
		my $targetPixelDensity = 0;
		my @targetPixelDensities = 	$scaledTexturePackerFileElement->getElementsByTagName('targetPixelDensity');
		if(scalar(@targetPixelDensities)){ $targetPixelDensity = $targetPixelDensities[0]->textContent;}

		my $targetResolutionX = 0;
		my $targetResolutionY = 0;
		my @targetResolutions = $scaledTexturePackerFileElement->getElementsByTagName('targetResolution');
		if(scalar(@targetResolutions)){
			#x and y ordinates are required in a target resolution, and there is a maximum of one target resolution		
			$targetResolutionX = ($scaledTexturePackerFileElement->getElementsByTagName('x'))[0]->textContent;
			$targetResolutionY = ($scaledTexturePackerFileElement->getElementsByTagName('y'))[0]->textContent;
		}
		
		$textureFiles[$scaleCount] = [	$scaleFactor,
										$targetPixelDensity,
										$targetResolutionX,
										$targetResolutionY]; #N.B. no texture frame data yet
		
		foreach my $texturePackerFileElement ($scaledTexturePackerFileElement->getElementsByTagName('texturePackerFile')){
			#Texture Packer file name element is required in xsd, so no validation of existence
			my $texturePackerFileName = $texturePackerFileElement->textContent;
			my $texturePackerDoc = $parserLibXML->parse_file($texturePackerFileName);
			#TODO: validate TexturePacker document if and when a schema is available
		
			if ($texturePackerDoc){
				my @animGuidCheckList = ''; #stores a true value at the index of a GUID, if a sprite
											#frame is found in the texture files that matches it
			
				foreach my $textureAtlasElement ($texturePackerDoc->getElementsByTagName('TextureAtlas')){

					my $imagePath = '';
					if($textureAtlasElement->hasAttribute('imagePath')){
						$imagePath = $textureAtlasElement->getAttribute('imagePath');
										
						foreach my $spriteElement ($textureAtlasElement->getElementsByTagName('sprite')){
							my $spriteN = ''; #file name
							my $spriteX = ''; #u ordinate
							my $spriteY = ''; #v ordinate
							my $spriteW = ''; #x dimension
							my $spriteH = ''; #y dimension
						
							my $spriteGuid = ''; #looked up in frameFileNameToGuid with $spriteN
						
							if(	$spriteElement->hasAttribute('n') &&
								$spriteElement->hasAttribute('x') &&
								$spriteElement->hasAttribute('y') &&
								$spriteElement->hasAttribute('w') &&
								$spriteElement->hasAttribute('h')){
							
								$spriteN = $spriteElement->getAttribute('n');
								$spriteX = $spriteElement->getAttribute('x');
								$spriteY = $spriteElement->getAttribute('y');
								$spriteW = $spriteElement->getAttribute('w');
								$spriteH = $spriteElement->getAttribute('h');
							}
							else{
								print "ERROR: Missing TexturePacker sprites' \"x\", \"y\", \"w\", or \"h\" attributes\n";
								exit 1;
							}
						
							if($spriteW && $spriteH){						#check the sprite has dimensions
								if(exists $frameFileNameToGuid{$spriteN}){	#check the file name has an associated GUID in the animations
									$spriteGuid = $frameFileNameToGuid{$spriteN};
								
									if($animGuidCheckList[$spriteGuid]){ #check animGuidCheckList
										print "WARNING: sprite with duplicate GUID=$spriteGuid ($spriteN) found in texture $imagePath\n";
									}
									else{
										$animGuidCheckList[$spriteGuid] = 1;
										push( @{$textureFiles[$scaleCount][4]{$imagePath}}, [$spriteGuid,$spriteX,$spriteY,$spriteW,$spriteH]);
									}
								}
								else{ print "WARNING: TexturePacker sprite unused in animations: $spriteN\n";}
							}
							else{
								print "ERROR: TexturePacker sprite has zero area\n";
								exit 1;
							}
						}
					
						#sort sprite frames by GUID, used as array index, for optimised storage at run time
						@{$textureFiles[$scaleCount][4]{$imagePath}} = sort {$a->[0]<=>$b->[0]} @{$textureFiles[$scaleCount][4]{$imagePath}};
					
						#validate that the number of frame GUIDs issued matches the number of stored sprite frames
						if(scalar(@{$textureFiles[$scaleCount][4]{$imagePath}}) != ($animFrameGuidCount)){
						print 	"WARNING: number of used frames contained within $imagePath = ".
								scalar(@{$textureFiles[$scaleCount][4]{$imagePath}}).", but number of frame GUIDs issued for ".
								"animations is ".$animFrameGuidCount."\n";
						for(my $guid=0;$guid<scalar(@animGuidCheckList);$guid++){
							if(!$animGuidCheckList[$guid]){
								print "WARNING: missing texture sprite for animation frame GUID=$guid:\n".
								"	$guidToFrameFileName[$guid]\n";
							}
						}
				}
					}
					else{
						print "ERROR: Missing TexturePacker TextureAtlas' \"imagePath\" attribute\n";
						exit 1;
					}				
				}
			}
		}
		
		$scaleCount++;
	}
	
	#DEBUG
	#print Dumper(@textureFiles);
		
	#************* For each gameXml document *************#

	#read in existing document, and replace the animation and texture data
	foreach my $gameXmlFileElement ($paramDoc->getElementsByTagName('gameXml')){
		
		my $gameXmlFilePath = $gameXmlFileElement->textContent;
		
		#cater for non-existent document, and create new one
		my $gameXmlDoc = '';
		my $gameConfigElement = ''; #the root element of the document
		if(-e $gameXmlFilePath){$gameXmlDoc = $parserLibXML->parse_file($gameXmlFilePath);}
		else{
			$gameXmlDoc = XML::LibXML::Document->new('1.0','UTF-8');
			$gameConfigElement = $gameXmlDoc->createElement('gameConfig');
			$gameXmlDoc->setDocumentElement($gameConfigElement);
		}
		
		#use the directory of the XML doc as a search path for the schema
		my $gameXmlSchema = '';
		my ($gameXmlFileName,$gameXmlDirectory,$gameXmlSuffixes) = fileparse($gameXmlFilePath);

		if(-e $gameXmlDirectory."gameXml.xsd"){
			$gameXmlSchema = XML::LibXML::Schema->new('location' => $gameXmlDirectory."gameXml.xsd");
			eval {$gameXmlSchema->validate($gameXmlDoc);};
			die $@ if $@;
		}
		else{
			print "WARNING: gameXml.xsd could not be found in the same directory to ".
			"validate the original $gameXmlFilePath file.\n";
		}
				
		#find the scaledArtIndex elements and delete them
		foreach my $scaledAnimationsElement ($gameXmlDoc->getElementsByTagName('scaledArtIndex')){
			my $gameConfigElement = $scaledAnimationsElement->parentNode;
			$gameConfigElement->removeChild($scaledAnimationsElement);
		}
		
		#N.B. there should only be one gameConfig element at most
		my @gameConfigElements = $gameXmlDoc->getElementsByTagName('gameConfig');
		if(scalar(@gameConfigElements)){$gameConfigElement = $gameConfigElements[0]}
		else{
			print "ERROR: missing gameConfig root element in gameXml\n";
		}
		
		for(my $scaleCount=0;$scaleCount<scalar(@textureFiles);$scaleCount++){		
			#create scaledArtIndexElement element per scale
			
			my $scaleFactor = $textureFiles[$scaleCount][0];

			my $scaledArtIndexElement = $gameXmlDoc->createElement('scaledArtIndex');
			$scaledArtIndexElement->setAttribute('numSprites',($animFrameGuidCount));
			$scaledArtIndexElement->setAttribute('numAnimations',scalar(@animations));
			$scaledArtIndexElement->setAttribute('numTextureFiles',scalar(keys %{$textureFiles[$scaleCount][4]}));
			#optional elements
			if($textureFiles[$scaleCount][1]){
				$scaledArtIndexElement->appendTextChild('targetPixelDensity',$textureFiles[$scaleCount][1]);
			}
			if($textureFiles[$scaleCount][2] || $textureFiles[$scaleCount][3]){
				my $targetResolutionElement = $gameXmlDoc->createElement('targetResolution');
				$targetResolutionElement->appendTextChild('x',$textureFiles[$scaleCount][2]);
				$targetResolutionElement->appendTextChild('y',$textureFiles[$scaleCount][3]);
				$scaledArtIndexElement->appendChild($targetResolutionElement);
			}

			#add textureFile information
			for my $imagePath (keys %{$textureFiles[$scaleCount][4]}){				
				my($textureFileName,$textureFileDirectory,$textureFileSuffix) = fileparse($imagePath);
				
				my $textureFileElement = $gameXmlDoc->createElement('textureFile');
				#use runtime texture directory override if specified
				if(length($runtimeTextureDirectory)){$textureFileElement->appendTextChild('dir',$runtimeTextureDirectory);}
				else{$textureFileElement->appendTextChild('dir',$textureFileDirectory);}
				$textureFileElement->appendTextChild('file',($textureFileName.$textureFileSuffix));
				
				for(my $spriteCount = 0;
					$spriteCount < scalar(@{$textureFiles[$scaleCount][4]{$imagePath}});
					$spriteCount++){
					
					my $spriteElement = $gameXmlDoc->createElement('sprite');
					$spriteElement->setAttribute('uid',$spriteCount);
					my $uvElement = $gameXmlDoc->createElement('uv');
					$uvElement->appendTextChild('x',$textureFiles[$scaleCount][4]{$imagePath}[$spriteCount][1]);
					$uvElement->appendTextChild('y',$textureFiles[$scaleCount][4]{$imagePath}[$spriteCount][2]);
					$spriteElement->appendChild($uvElement);
					my $dimensionsElement = $gameXmlDoc->createElement('dimensions');
					$dimensionsElement->appendTextChild('x',$textureFiles[$scaleCount][4]{$imagePath}[$spriteCount][3]);
					$dimensionsElement->appendTextChild('y',$textureFiles[$scaleCount][4]{$imagePath}[$spriteCount][4]);
					$spriteElement->appendChild($dimensionsElement);

					$textureFileElement->appendChild($spriteElement);
				}
			
				$scaledArtIndexElement->appendChild($textureFileElement);
			}
				
			#iterate through animations, scaling and storing them
			for(my $animGuid = 0; $animGuid < scalar(@animations); $animGuid++){
				my $animationElement = $gameXmlDoc->createElement('animation');
				$animationElement->setAttribute('uid',$animGuid);
				$animationElement->appendTextChild('name',$animations[$animGuid][0]);
				$animationElement->setAttribute('numAnimationFrames',scalar(@{$animations[$animGuid][1]}));
				$animationElement->setAttribute('animationLengthMilliSec',$animations[$animGuid][2]);
			
				#scale and store animation frame timings
				for(my $frameTimingCount = 0;$frameTimingCount< scalar(@{$animations[$animGuid][1]});$frameTimingCount++){
					#default is to round translates to whole pixels to preserve original art					
					my $scaledTranslateX = int($animations[$animGuid][1][$frameTimingCount][3]*$scaleFactor);
					my $scaledTranslateY = int($animations[$animGuid][1][$frameTimingCount][4]*$scaleFactor);
				
					#DEBUG
					#print "DEBUG: [$animations[$animGuid][1][$frameTimingCount][0],".
					#				"$animations[$animGuid][1][$frameTimingCount][1],".
					#				"$animations[$animGuid][1][$frameTimingCount][2],".
					#				"$scaledTranslateX,".
					#				"$scaledTranslateY]\n";
				
					my $animationFrameElement = $gameXmlDoc->createElement('animationFrame');
					$animationFrameElement->appendTextChild('spriteUid',$animations[$animGuid][1][$frameTimingCount][0]);
					$animationFrameElement->appendTextChild('startTimeMilliSec',$animations[$animGuid][1][$frameTimingCount][1]);
					$animationFrameElement->appendTextChild('endTimeMilliSec',$animations[$animGuid][1][$frameTimingCount][2]);
					my $translateElement = $gameXmlDoc->createElement('translate');
					$translateElement->appendTextChild('x',$scaledTranslateX);
					$translateElement->appendTextChild('y',$scaledTranslateY);
					$animationFrameElement->appendChild($translateElement);
					
					$animationElement->appendChild($animationFrameElement);
				}
				
				$scaledArtIndexElement->appendChild($animationElement);
			}

			$gameConfigElement->appendChild($scaledArtIndexElement);
		}		
		
		#validate altered document with gameXml.xsd
		if($gameXmlSchema){
			eval {$gameXmlSchema->validate($gameXmlDoc);};
			if($@){
				print "ERROR: schema validation for $gameXmlFilePath:\n$@";
				exit;
			}
		}
		else{
			print "WARNING: gameXml.xsd could not be found to validate ".
			"altered $gameXmlFilePath file.\n";
		}
		
		#output to original file name
		open (my $gameXmlFile_fh, '>', $gameXmlFilePath);
		print {$gameXmlFile_fh} $gameXmlDoc->toString(1); #indent for readability
	}
}
