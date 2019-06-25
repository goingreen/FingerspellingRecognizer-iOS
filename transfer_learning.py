#!/usr/bin/env python
# coding: utf-8


from __future__ import absolute_import, division, print_function

import os
import keras

import numpy as np

import matplotlib.pyplot as plt
import matplotlib.image as mpimg

image_size = 224
batch_size = 32

# Rescale all images by 1./255 and apply image augmentation
datagen = keras.preprocessing.image.ImageDataGenerator(
                rotation_range=12,
                shear_range=0.04,
                width_shift_range=0.08,
                height_shift_range=0.04,
                zoom_range=[0.94, 1.04],
                fill_mode='constant',
                cval=0,
                horizontal_flip=True,
                rescale=1./255)

train_dataset_dir = "fingerspelling-iphone"
train_generator = datagen.flow_from_directory(
                train_dataset_dir,
                target_size=(image_size, image_size),  
                batch_size=batch_size)


val_datagen = keras.preprocessing.image.ImageDataGenerator(
                rescale=1./255)
val_dataset_dir = "fingerspelling-validation"
validation_generator = val_datagen.flow_from_directory(
                val_dataset_dir,
                target_size=(image_size, image_size),  
                batch_size=batch_size,
                shuffle=False)


IMG_SHAPE = (image_size, image_size, 3)

base_model = keras.applications.MobileNetV2(input_shape=IMG_SHAPE,
                                               include_top=False, 
                                               weights='imagenet')

base_model.trainable = False

model = keras.Sequential([
  base_model,
  keras.layers.GlobalAveragePooling2D(),
  keras.layers.Dense(31, activation='softmax')
])

model.compile(optimizer=keras.optimizers.RMSprop(lr=1e-4), 
              loss='categorical_crossentropy', 
              metrics=['accuracy'])

# ### Train the model
steps_per_epoch = train_generator.n // batch_size
validation_steps = validation_generator.n // batch_size

history = model.fit_generator(train_generator, 
                              steps_per_epoch = steps_per_epoch,
                              epochs=10, 
                              workers=4,
                              validation_data=validation_generator, 
                              validation_steps=validation_steps)

acc = history.history['acc']
val_acc = history.history['val_acc']

loss = history.history['loss']
val_loss = history.history['val_loss']

plt.figure(figsize=(12, 12))
plt.subplot(2, 1, 1)
plt.plot(acc, label='Точность обучения')
plt.plot(val_acc, label='Точность валидации')
plt.legend(loc='lower right')
#plt.ylabel('Accuracy')
plt.ylim([min(plt.ylim()),1])
plt.title('Точность')

plt.subplot(2, 1, 2)
plt.plot(loss, label='Функция ошибки обучения')
plt.plot(val_loss, label='Функция ошибки валидации')
plt.legend(loc='upper right')
plt.ylabel('Cross Entropy')
plt.ylim([0,max(plt.ylim())])
plt.title('Функция ошибки')
plt.show()


print("Number of layers in the base model: ", len(base_model.layers))
base_model.trainable = True

fine_tune_at = 73
for layer in base_model.layers[:fine_tune_at]:
  layer.trainable =  False
for layer in base_model.layers[fine_tune_at:]:
  layer.trainable =  True

for i, layer in enumerate(base_model.layers):
    print(i, layer.name, layer.trainable)

model.compile(loss='categorical_crossentropy',
              optimizer = keras.optimizers.RMSprop(lr=1e-6),
              metrics=['accuracy'])


history_fine = model.fit_generator(train_generator, 
                                   steps_per_epoch = steps_per_epoch,
                                   epochs=4, 
                                   workers=4,
                                   validation_data=validation_generator, 
                                   validation_steps=validation_steps)
acc += history_fine.history['acc']
val_acc += history_fine.history['val_acc']

loss += history_fine.history['loss']
val_loss += history_fine.history['val_loss']

plt.figure(figsize=(12, 12))
plt.subplot(2, 1, 1)
plt.plot(acc, label='Точность обучения')
plt.plot(val_acc, label='Точность валидации')
plt.ylim([0, 1])
plt.legend(loc='lower right')
plt.title('Точность')

plt.subplot(2, 1, 2)
plt.plot(loss, label='Функция ошибки обучения')
plt.plot(val_loss, label='Функция ошибки валидации')
plt.ylim([0, 4])
plt.legend(loc='upper right')
plt.title('Функция ошибки')
plt.show()

history_fine = model.fit_generator(train_generator,
                                   steps_per_epoch = steps_per_epoch,
                                   epochs=4, 
                                   workers=4,
                                   callbacks=[metrics])
acc += history_fine.history['acc']
val_acc += history_fine.history['val_acc']

loss += history_fine.history['loss']
val_loss += history_fine.history['val_loss']

from sklearn.metrics import confusion_matrix, classification_report
Y_pred = model.predict_generator(test_generator,
                                 workers=4,
                                 steps=test_generator.n // batch_size+1)
y_pred = np.argmax(Y_pred, axis=1)
print('Confusion Matrix')
print(confusion_matrix(test_generator.classes, y_pred))
print('Classification Report')
print(classification_report(test_generator.classes, y_pred))

model.save("my_model.h5")

import coremltools

coreml_model = coremltools.converters.keras.convert(model,
                                                    input_names="image",
                                                    output_names="result",
                                                    image_input_names="image",
                                                    image_scale = 1./255,
                                                    class_labels="classLabels.txt")

coreml_model.save("fingerspelling_recognizer_new.mlmodel")


from keras.callbacks import Callback
from sklearn.metrics import confusion_matrix, classification_report
import pandas as pd
class Metrics(Callback):
    def on_epoch_end(self, epoch, logs={}):
        validation_generator.reset()
        Y_pred = model.predict_generator(validation_generator,
                                         workers=4,
                                         steps=validation_generator.n // batch_size+1)
        y_pred = np.argmax(Y_pred, axis=1)
        print('Classification Report')
        report = classification_report(validation_generator.classes, y_pred, output_dict=True)
        dataframe = pd.DataFrame(report).transpose()
        dataframe.to_csv('classification_report.csv', index = False)
        return
 
metrics = Metrics()

import pandas as pd
validation_generator.reset()
Y_pred = model.predict_generator(validation_generator,
                                 workers=4,
                                 steps=validation_generator.n // batch_size+1)
y_pred = np.argmax(Y_pred, axis=1)
print('Classification Report')
report = classification_report(validation_generator.classes, y_pred, output_dict=True)
dataframe = pd.DataFrame(report).transpose()
dataframe.to_csv('classification_report.csv', float_format='%.3f', index = False)
