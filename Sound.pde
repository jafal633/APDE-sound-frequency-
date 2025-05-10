import android.media.AudioRecord;
import android.media.AudioFormat;
import android.media.MediaRecorder;

// Audio configuration
int sampleRate = 44100;
int bufferSize = 1024;
short[] audioBuffer;
AudioRecord audioRecord;

// Visualization variables
float[] volumes = new float[100];
int volumeIndex = 0;
float smoothVolume = 0;
float smoothingFactor = 0.2;
float peakVoltage = 0;
float peakDecay = 0.995;

// Frequency detection
float currentFrequency = 0;
float[] spectrum = new float[50];
color[] spectrumColors = new color[50];

// UI Elements
Slider volumeSlider;
Slider fftBandsSlider;
int fftBands = 20;
int currentMode = 0; // 0=spectrum, 1=waveform, 2=oscilloscope
boolean showSliders = true;

void setup() {
  fullScreen();
  orientation(LANDSCAPE);
  noStroke();
  
  // Initialize spectrum colors
  for (int i = 0; i < spectrumColors.length; i++) {
    spectrumColors[i] = color(
      map(i, 0, spectrumColors.length, 150, 255),
      map(i, 0, spectrumColors.length, 255, 150),
      100
    );
  }
  
  // Audio setup
  audioBuffer = new short[bufferSize];
  audioRecord = new AudioRecord(
    MediaRecorder.AudioSource.MIC,
    sampleRate,
    AudioFormat.CHANNEL_IN_MONO,
    AudioFormat.ENCODING_PCM_16BIT,
    bufferSize * 2);
  
  // Create sliders
  int sliderHeight = height/12;
  int padding = sliderHeight/2;
  
  volumeSlider = new Slider(
    padding, 
    height - padding - sliderHeight*2, 
    width - padding*2, 
    sliderHeight, 
    10, 200, 
    "Gain");
  volumeSlider.setValue(100);
  
  fftBandsSlider = new Slider(
    padding, 
    height - padding - sliderHeight, 
    width - padding*2, 
    sliderHeight, 
    5, 50, 
    "Bands");
  fftBandsSlider.setValue(20);
  
  // Check permissions
  if (!hasPermission("android.permission.RECORD_AUDIO")) {
    requestPermission("android.permission.RECORD_AUDIO");
  } else {
    startMonitoring();
  }
}

void draw() {
  background(0);
  
  // Process audio
  fftBands = (int)fftBandsSlider.getValue();
  int samplesRead = audioRecord.read(audioBuffer, 0, bufferSize);
  
  if (samplesRead > 0) {
    // Calculate volume with gain
    float gain = volumeSlider.getValue()/100.0;
    float currentPeak = 0;
    
    for (int i = 0; i < samplesRead; i++) {
      float sample = abs(audioBuffer[i]) / 32768.0 * gain;
      if (sample > currentPeak) currentPeak = sample;
    }
    
    // Update peak voltage (with decay)
    if (currentPeak > peakVoltage) {
      peakVoltage = currentPeak;
    } else {
      peakVoltage *= peakDecay;
    }
    
    // Calculate average volume
    float sum = 0;
    for (int i = 0; i < samplesRead; i++) {
      sum += abs(audioBuffer[i]) / 32768.0 * gain;
    }
    float avgVolume = sum / samplesRead;
    
    // Smooth volume
    smoothVolume = smoothingFactor * avgVolume + (1-smoothingFactor)*smoothVolume;
    volumes[volumeIndex] = smoothVolume;
    volumeIndex = (volumeIndex + 1) % volumes.length;
    
    // Frequency detection
    currentFrequency = detectFrequency(audioBuffer, samplesRead);
    
    // Update spectrum
    updateSpectrum();
    
    // Draw visualization
    switch(currentMode) {
      case 0: drawSpectrum(); break;
      case 1: drawWaveform(); break;
      case 2: drawOscilloscope(); break;
    }
  }
  
  // Draw UI
  drawUI();
}

float detectFrequency(short[] buffer, int length) {
  int zeroCrossings = 0;
  boolean wasPositive = buffer[0] > 0;
  
  for (int i = 1; i < length; i++) {
    boolean isPositive = buffer[i] > 0;
    if (isPositive != wasPositive) {
      zeroCrossings++;
      wasPositive = isPositive;
    }
  }
  
  float duration = length / (float)sampleRate;
  float frequency = (zeroCrossings / 2.0) / duration;
  
  return (frequency > 50 && frequency < 2000) ? frequency : 0;
}

void updateSpectrum() {
  int bands = spectrum.length;
  int samplesPerBand = bufferSize/bands;
  
  for (int b = 0; b < min(fftBands, bands); b++) {
    float sum = 0;
    int start = b * samplesPerBand;
    int end = min((b+1)*samplesPerBand, bufferSize);
    
    for (int i = start; i < end; i++) {
      sum += abs(audioBuffer[i]) / 32768.0;
    }
    
    spectrum[b] = 0.2*(sum/(end-start)) + 0.8*spectrum[b];
  }
}

void drawWaveform() {
  noFill();
  stroke(100, 255, 100, 150);
  strokeWeight(2);
  beginShape();
  for (int i = 0; i < min(bufferSize, width); i++) {
    float x = map(i, 0, min(bufferSize, width), 0, width);
    float y = map(audioBuffer[i]/32768.0, -1, 1, height*0.3, height*0.7);
    vertex(x, y);
  }
  endShape();
}

void drawSpectrum() {
  noStroke();
  float bandWidth = width / (float)fftBands;
  
  for (int i = 0; i < min(fftBands, spectrum.length); i++) {
    float h = map(spectrum[i], 0, 0.5, 0, height*0.6);
    float x = i * bandWidth;
    float y = height - h;
    
    fill(spectrumColors[i % spectrumColors.length]);
    rect(x, y, bandWidth-2, h);
  }
}

void drawOscilloscope() {
  // Draw grid
  stroke(50);
  strokeWeight(1);
  for (int y = 0; y < height; y += height/10) {
    line(0, y, width, y);
  }
  for (int x = 0; x < width; x += width/10) {
    line(x, 0, x, height);
  }
  
  // Draw waveform
  noFill();
  stroke(0, 255, 0);
  strokeWeight(2);
  beginShape();
  for (int i = 0; i < min(bufferSize, width); i++) {
    float x = map(i, 0, min(bufferSize, width), 0, width);
    float y = map(audioBuffer[i]/32768.0, -1, 1, height*0.1, height*0.9);
    vertex(x, y);
  }
  endShape();
  
  // Draw peak voltage indicator
  float peakY = map(peakVoltage, 0, 1, height*0.9, height*0.1);
  stroke(255, 0, 0);
  line(0, peakY, width, peakY);
  
  // Display peak voltage
  fill(255, 0, 0);
  textSize(30);
  textAlign(RIGHT, TOP);
  text("Peak: " + nf(peakVoltage*100, 1, 1) + "%", width-20, 20);
}

void drawUI() {
  // Draw sliders if visible
  if (showSliders) {
    volumeSlider.draw();
    fftBandsSlider.draw();
  }
  
  // Mode button
  drawButton(width - 150, 50, 100, 50, "Mode", color(100));
  
  // Toggle sliders button
  drawButton(width - 150, 120, 100, 50, showSliders ? "Hide UI" : "Show UI", color(80, 80, 120));
  
  // Frequency display
  fill(200, 240, 255);
  textSize(36);
  textAlign(CENTER);
  text(nf(currentFrequency, 1, 1) + " Hz", width/2, 50);
  
  // Mode indicator
  String[] modeNames = {"Spectrum", "Waveform", "Oscilloscope"};
  fill(200);
  textSize(24);
  textAlign(LEFT, TOP);
  text("Mode: " + modeNames[currentMode], 20, 20);
}

void drawButton(float x, float y, float w, float h, String label, color btnColor) {
  fill(btnColor);
  rect(x, y, w, h, 10);
  fill(255);
  textSize(20);
  textAlign(CENTER, CENTER);
  text(label, x + w/2, y + h/2);
}

void mousePressed() {
  // Check slider controls
  if (showSliders) {
    if (volumeSlider.mousePressed()) return;
    if (fftBandsSlider.mousePressed()) return;
  }
  
  // Check mode button (top-right)
  if (mouseX > width - 150 && mouseX < width - 50 && 
      mouseY > 50 && mouseY < 100) {
    currentMode = (currentMode + 1) % 3; // Cycle between 3 modes
  }
  
  // Check UI toggle button (below mode button)
  if (mouseX > width - 150 && mouseX < width - 50 && 
      mouseY > 120 && mouseY < 170) {
    showSliders = !showSliders;
  }
}

void mouseDragged() {
  if (showSliders) {
    if (volumeSlider.mouseDragged()) return;
    if (fftBandsSlider.mouseDragged()) return;
  }
}

void mouseReleased() {
  if (showSliders) {
    volumeSlider.mouseReleased();
    fftBandsSlider.mouseReleased();
  }
}

class Slider {
  float x, y, w, h;
  float minVal, maxVal;
  float value;
  boolean dragging = false;
  String label;
  
  Slider(float x, float y, float w, float h, float minVal, float maxVal, String label) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.minVal = minVal;
    this.maxVal = maxVal;
    this.label = label;
    this.value = minVal;
  }
  
  void setValue(float val) {
    value = constrain(val, minVal, maxVal);
  }
  
  float getValue() {
    return value;
  }
  
  void draw() {
    // Track
    fill(100);
    rect(x, y, w, h, h/2);
    
    // Thumb
    float thumbX = map(value, minVal, maxVal, x, x + w);
    fill(200);
    ellipse(thumbX, y + h/2, h * 1.5, h * 1.5);
    
    // Label and value
    fill(255);
    textSize(h * 0.6);
    textAlign(LEFT, CENTER);
    text(label + ": " + nf(value, 1, 1), x, y - h);
  }
  
  boolean mousePressed() {
    if (mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h) {
      dragging = true;
      return true;
    }
    return false;
  }
  
  boolean mouseDragged() {
    if (dragging) {
      value = constrain(map(mouseX, x, x + w, minVal, maxVal), minVal, maxVal);
      return true;
    }
    return false;
  }
  
  void mouseReleased() {
    dragging = false;
  }
}

void startMonitoring() {
  if (audioRecord.getState() == AudioRecord.STATE_INITIALIZED) {
    audioRecord.startRecording();
  }
}

void onPermissionGranted(String permission) {
  if (permission.equals("android.permission.RECORD_AUDIO")) {
    startMonitoring();
  }
}

void onPause() {
  if (audioRecord.getState() == AudioRecord.RECORDSTATE_RECORDING) {
    audioRecord.stop();
  }
  super.onPause();
}

void onDestroy() {
  if (audioRecord != null) {
    audioRecord.release();
  }
  super.onDestroy();
}
